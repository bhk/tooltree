#define _GNU_SOURCE

#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>

#include <fcntl.h>      // open
#include <sys/types.h>  // stat
#include <sys/stat.h>   // stat

#ifdef _MSC_VER
# include <io.h>
# define open(n,f) _open(n, (f) | _O_BINARY)
# define read _read
# define close _close
# define vsnprintf _vsnprintf
# pragma warning(disable : 4996) // this covers POSIX and _CRT_SECURE_NO_DEPRECATE warnings
# define _CRT_SECURE_NO_WARNINGS
#else
# include <unistd.h>     // read, close
#endif

#include "strutil.h"

#define BETWEEN(x, ge, lt)    ( (unsigned) ((x) - (ge)) <  (unsigned) ((lt) - (ge)) )


//------------------------------------------------------------
// Misc.
//------------------------------------------------------------


void *Zalloc(size_t n)
{
   void *pv = malloc(n);
   memset(pv, 0, n);
  return pv;
}



void Error(CStr msg)
{
   fprintf(stderr, "ERROR: %s\n", msg);
   exit(-1);
}


void Error1(CStr msg, CStr arg)
{
   fprintf(stderr, "ERROR: %s (%s)\n", msg, arg);
   exit(-1);
}


void Require(int bTrue, CStr msg)
{
   if (!bTrue) {
      Error(msg);
   }
}


//------------------------------------------------------------
// Str
//------------------------------------------------------------

Str Str_Dup(CStr s)
{
  return strdup(s);
}


Str Str_NewSize(CStr psz, size_t size)
{
   Str me = (Str) malloc(size+1);

   memmove(me, psz, size);
   me[size] = '\0';
   return me;
}


CStr Str_End(CStr psz)
{
   return psz + strlen(psz);
}


Str Str_Cat3(CStr a, CStr b, CStr c)
{
   size_t lenA = strlen(a);
   size_t lenB = strlen(b);
   size_t lenC = strlen(c);
   Str me = (Str) malloc(lenA + lenB + lenC + 1);

   memmove(me, a, lenA);
   memmove(me+lenA, b, lenB);
   memmove(me+lenA+lenB, c, lenC+1);

   return me;
}


int Str_Begins(CStr pszPrefix, CStr str)
{
   char ch;
   while ((ch = *pszPrefix++) != '\0') {
      if (ch != *str) {
         return 0;
      }
      ++str;
   }
   return 1;
}


int Str_EQ(CStr a, CStr b)
{
   return strcmp(a,b) == 0;
}


Str Str_Cat(CStr a, CStr b)
{
   size_t lenA = strlen(a);
   size_t lenB = strlen(b);
   Str me = (Str) malloc(lenA + lenB + 1);

   memmove(me, a, lenA);
   memmove(me+lenA, b, lenB+1);
   return me;
}

Str Str_ToUpper(CStr psz)
{
   Str pout = strdup(psz);
   Str p = pout;

   for (p = pout; *p; ++p) {
      if (BETWEEN(*p, 'a', 'z'+1)) {
         *p = (char) (*p - 32);
      }
   }
   return pout;
}


//------------------------------------------------------------
// SList & SNode
//------------------------------------------------------------


static __inline unsigned FingerPrint(CStr pszKey)
{
   unsigned n = 0;
   while (*pszKey) {
      n = (n + (unsigned char) *pszKey++) * 11777;
   }
   return n;
}


SNode *SNode_New(CStr psz)
{
   SNode *me = NEW(SNode);
   me->pNext = 0;
   me->psz = psz;
   me->uPrint = FingerPrint(psz);
   return me;
}

void SList_Ctor(SList *me)
{
   me->psnFirst = 0;
}


SList * SList_New(void)
{
   SList *me = NEW(SList);
   SList_Ctor(me);
   return me;
}


SNode **SList_End(SList *me)
{
   SNode **pp = &me->psnFirst;
   while ( *pp ) {
      pp  = &(*pp)->pNext;
   }
   return pp;
}

void SList_Append(SList *me, CStr psz)
{
   SNode **pp = SList_End(me);
   *pp = SNode_New(psz);
}

void SList_AppendList(SList *me, SList *psl)
{
   SNode **pp = SList_End(me);
   *pp = psl->psnFirst;
}

void SList_AppendUnique(SList *me, CStr psz)
{
   unsigned u = FingerPrint(psz);
   SNode *p, **pp = &me->psnFirst;

   while ( (p = *pp) != 0 ) {
      if (u == p->uPrint && Str_EQ(p->psz, psz)) {
         return;
      }
      pp  = &p->pNext;
   }

   *pp = SNode_New(psz);
}


#if 0
void SList_WriteLines(SList *me, FILE *f)
{
   SNode *psn;
   SLIST_FORALL(me, psn) {
      fprintf(f, "%s\n", psn->psz);
   }

   if (me->psnFirst) {
      fprintf(f, "\n");
   }
}
#endif

int SList_IsEmpty(SList *me)
{
   return (me->psnFirst == 0);
}



//------------------------------------------------------------
// GetLine
//------------------------------------------------------------

#ifndef GETLINE_SIZE
# define GETLINE_SIZE  16000
#endif

struct GetLine {
  Str  pData;
  Str  pMax;
  Str  pNext;

  int  fd;
  int  bStrip;   // strip leading whitespace characters and skip entirely blank lines
};


// Read more data from a file into the buffer
//
// Return TRUE if it called read(); buffer conents are shifted to start
// Return FALSE if there is no more data; buffer is undisturbed.
//
int GetLine_ReadMore(GetLine *me)
{
   Str pData = me->pData;
   Str pNext = me->pNext;
   int fd = me->fd;

   if (fd >= 0 && pNext > pData) {
      Str pMax = me->pMax;
      size_t cb = (size_t) (pMax - pNext);
      Str pNew = pData + cb;
      int n;

      memmove(pData, pNext, cb);
      me->pNext = pData;

      do {
         n = read(fd, pNew, (size_t) (pMax - pNew));
         if (n < 0) {
            Error("read error");
         }
         pNew += n;
      } while (n > 0 && pNew < pMax);

      if (n == 0) {
         close(fd);
         me->fd = -1;
      }
      me->pMax = pNew;
      return 1;
   }
   return 0;
}


// Get next line as zero-terminated string.
//
// If line is larger than getline buffer, return that many bytes as a line.
//
//
Str GetLine_Next(GetLine *me)
{
   Str pmax = me->pMax;
   Str p = me->pNext;
   Str pStart;

   if (me->bStrip) {
      // can speed up later processing
      pmax[0] = '!';
      p = Str_SkipWhiteNC(p);
   }

   pStart = p;
   pmax[0] = '\n';
   while (*p != '\n') {
      ++p;
   }

   *p = '\0';
   if (p < pmax) {
      if (p > pStart && p[-1] == '\r') {
         p[-1] = '\0';
      }
      ++p;
   } else if (GetLine_ReadMore(me)) {
      return GetLine_Next(me);
   } else if (p == me->pNext) {
      // end of stream: terminate line only if non-empty
      return 0;
   }

   me->pNext = p;
   return pStart;
}



void GetLine_Delete(GetLine *me)
{
   if (me->fd >= 0) {
      close(me->fd);
   }
   free(me->pData);
   free(me);
}


GetLine *GetLine_NewBuffer(CStr psz)
{
   GetLine *me = NEW(GetLine);

   me->pData = strdup(psz);
   me->pMax = me->pData + strlen(psz);
   me->pNext = me->pData;
   me->fd = -1;

   return me;
}


GetLine *GetLine_NewFile(CStr pszFile, int bStrip)
{
   GetLine *me = NEW(GetLine);

   me->pData = (Str) malloc((size_t) (GETLINE_SIZE+1));
   me->pMax = me->pData + GETLINE_SIZE;
   me->pNext = me->pMax;
   me->bStrip = bStrip;

   me->fd = open(pszFile, O_RDONLY);

   if (!GetLine_ReadMore(me)) {
      GetLine_Delete(me);
      return 0;
   }

   return me;
}


//------------------------------------------------------------
// Hash
//------------------------------------------------------------

#define HASHSIZE   128

static __inline unsigned HashFunc(CStr pszKey)
{
#if HASHSIZE > 1
   return (unsigned) (HASHSIZE-1) & (FingerPrint(pszKey) >> 8);
#else
   return 0;
#endif
}

struct Hash {
  HashNode *pFirst[HASHSIZE];
};


Hash *Hash_New(void)
{
   Hash *me = NEW(Hash);
   ZEROPTR(me);
   return me;
}

HashNode *Hash_Find(Hash *me, CStr pszKey)
{
   HashNode *p = me->pFirst[HashFunc(pszKey)];

   for (; p; p = p->pNext) {
      if (Str_EQ(p->psz, pszKey)) {
         return p;
      }
   }

   return 0;
}

int Hash_Get(Hash *me, CStr pszKey, void **ppv)
{
   HashNode *p = Hash_Find(me, pszKey);

   if (p) {
      *ppv = p->pv;
      return 1;
   }
   return 0;
}

void Hash_Insert(Hash *me, CStr pszKey, void *pv)
{
   HashNode *p = NEW(HashNode);
   unsigned h = HashFunc(pszKey);

   p->psz = pszKey;
   p->pv = pv;
   p->pNext = me->pFirst[h];
   me->pFirst[h] = p;
}

void Hash_Set(Hash *me, CStr pszKey, void *pv)
{
   HashNode *p = Hash_Find(me, pszKey);

   if (p) {
      p->pv = pv;
   } else {
      Hash_Insert(me, pszKey, pv);
   }
}

