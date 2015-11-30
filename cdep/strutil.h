#ifndef _STRUTIL_H_
#define _STRUTIL_H_

#ifdef __cplusplus
extern "C" {
#endif
#if 0
}
#endif


//------------------------------------------------------------
// Str
//------------------------------------------------------------


typedef const char *CStr;
typedef char *Str;


Str  Str_Dup(CStr s);
Str  Str_NewSize(CStr psz, size_t size);
CStr Str_End(CStr psz);
Str  Str_Cat3(CStr a, CStr b, CStr c);
int  Str_Begins(CStr pszPrefix, CStr str);
int  Str_EQ(CStr a, CStr b);
Str  Str_Cat(CStr a, CStr b);
Str  Str_ToUpper(CStr psz);

#define CHAR_ISWHITE(ch)  ((unsigned char) ((ch)-1) < (unsigned char) 32)

static __inline CStr Str_SkipWhite(CStr psz)
{
   while (CHAR_ISWHITE(*psz)) {
      ++psz;
   }
   return psz;
}


static __inline Str Str_SkipWhiteNC(Str psz)
{
   return psz + (Str_SkipWhite((CStr) psz) - ((CStr)psz));
}


static __inline int Char_IsAlnum(char ch)
{
   ch |= 32;
   return ( (ch >= 'a' && ch <= 'z') ||
            (ch >= '0' && ch <= '9') );
}


//------------------------------------------------------------
// SList & SNode
//------------------------------------------------------------


typedef struct SNode SNode;
struct SNode {
  SNode *pNext;
  CStr psz;
  unsigned uPrint;
};

typedef struct SList SList;
struct SList {
   SNode *psnFirst;
};


SNode *  SNode_New(CStr psz);

SList *  SList_New(void);
void     SList_Ctor(SList *me);
SNode ** SList_End(SList *me);
void     SList_Append(SList *me, CStr psz);
void     SList_AppendList(SList *me, SList *psl);
void     SList_AppendUnique(SList *me, CStr psz);
int      SList_IsEmpty(SList *me);


#define SLIST_FORALL(pl, p)   for (p = (pl)->psnFirst; p; p = p->pNext)


//------------------------------------------------------------
// GetLine
//------------------------------------------------------------


typedef struct GetLine GetLine;

GetLine * GetLine_NewBuffer(CStr psz);
GetLine * GetLine_NewFile(CStr pszFile, int bStrip);
int       GetLine_ReadMore(GetLine *me);
Str       GetLine_Next(GetLine *me);
void      GetLine_Delete(GetLine *me);

#define GETLINE_FORALL(pgl, p)   for (p = 0; (p = GetLine_Next((pgl))) != 0; )


//------------------------------------------------------------
// Hash
//------------------------------------------------------------


typedef struct Hash Hash;

typedef struct HashNode HashNode;
struct HashNode {
  HashNode *pNext;
  CStr      psz;
  void *    pv;
};

Hash *     Hash_New(void);
HashNode * Hash_Find(Hash *me, CStr pszKey);
int        Hash_Get(Hash *me, CStr pszKey, void **ppv);
void       Hash_Insert(Hash *me, CStr pszKey, void *pv);
void       Hash_Set(Hash *me, CStr pszKey, void *pv);


//------------------------------------------------------------
// Misc
//------------------------------------------------------------


#define NEW(t)  ((t*)Zalloc(sizeof(t)))
#define ZEROPTR(ptr)   memset((ptr), 0, sizeof(*(ptr)))
#define ZEROREC(rec)   memset(&(rec), 0, sizeof(rec))


void * Zalloc(size_t n);
void   Error(CStr msg);
void   Error1(CStr msg, CStr arg);
void   Require(int bTrue, CStr msg);



#ifdef __cplusplus
}
#endif

#endif /* _STRUTIL_H_ */
