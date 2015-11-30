#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>      // open
#include <sys/types.h>  // stat
#include <sys/stat.h>   // stat
#ifdef _MSC_VER
# include <io.h>
# define open(n,f) _open(n, (f) | _O_BINARY)
# define read _read
# define close _close
# pragma warning(disable : 4996) // this covers POSIX and _CRT_SECURE_NO_DEPRECATE warnings
# define _CRT_SECURE_NO_WARNINGS
  typedef unsigned long uintptr_t;
#else
# include <stdint.h>
# include <unistd.h>     // read, close
#endif

#include "strutil.h"


#define ZEROREC(rec)  memset(&(rec), 0, sizeof(rec))


// Notes:
//
// - This is a conservative dependency generator.  It does not do complete
//   pre-processing, so #ifdefs and multi-line comments may cause it to
//   produce a larger dependency set than necessary for a particular target.
//

// To do:
//
// - Option to display nesting trace for each header file ("how it got
//   included"), or for a particular header.
//
// - Option to output missing headers (not as warning; with nesting trace if
//   requested)
//


//------------------------------------------------------------
// Globals
//------------------------------------------------------------


typedef enum CDepScan {
  CDEPSCAN_ALL,       // dependencies
  CDEPSCAN_NORECURSE,     // immediate dependencies
  CDEPSCAN_NORESOLVE      // include directives (not resolved to file names)
} CDepScan;


typedef enum CDepOut {
  CDEPOUT_MAKE,         // make-style dependencies:  "object: dependency"
  CDEPOUT_MAKEPLUS,     // make-style plus empty line for each included file
  CDEPOUT_DEPS,         // depoendencies only
  CDEPOUT_STATS         // dependency statistics
} CDepOut;


CDepScan    gnScan = CDEPSCAN_ALL;
CDepOut     gnOut = CDEPOUT_MAKEPLUS;
CStr        gpszFields = "";

int         gbWarnMissing = 0;
int         gbStripPath = 0;
const char *gpszObject = 0;       // object name or directory
int         gbObjDir = 0;         // TRUE if gpszObject is a directory


//------------------------------------------------------------
// Misc Utilities
//------------------------------------------------------------

#define ARGV_DECLS         char **argv_ppa
#define ARGV_FORALL(a, p)  for (argv_ppa = a; (p = *argv_ppa) != 0; ++argv_ppa)
#define ARGV_INDEX(n)      (argv_ppa[n])
#define ARGV_SKIP(n)       (argv_ppa += (n))


//------------------------------------------------------------
// File Utilities
//------------------------------------------------------------


// pszDir can be a directrory or NULL.
//
static Str MakePath(CStr pszDir, CStr pszRel)
{
   if (!pszDir || !pszDir[0] || pszRel[0] == '/') {
      return Str_Dup(pszRel);
   }

   return Str_Cat3(pszDir, "/", pszRel);
}

// Remove redundant "./" and "x/../" occurrences
//
static void CleanPath_D(Str pszPath)
{
   Str p;
   Str pszMark;

   // normalize slashes (helps when running metrics on UNIX machines over
   // a code base that is not completely cross-platform)
   p = strchr(pszPath, '\\');
   if (p) {
      for (;*p; ++p) {
         if ('\\' == *p) *p = '/';
      }
   }

   p = pszPath;
   while (p[0] == '.' && p[1] == '/') {
      p += 2;
   }
   if (p > pszPath) {
      memmove(pszPath, p, strlen(p)+1);
   }

   p = pszPath;
   while ((p = strstr(p, "/./")) != 0) {
      memmove(p, p+2, strlen(p+1));
   }

   // Delete "xxx/../"
   pszMark = pszPath;
   while ((p = strstr(pszMark, "/../")) != 0) {
      Str pb = p;
      while (pb > pszMark && pb[-1] != '/') {
         --pb;
      }
      if (pb < p && !Str_Begins("../", pb)) {
         memmove(pb, p+4, strlen(p+3));
      } else {
         pszMark = p+4;    // skip beyond this to avoid endless loop
      }
   }
}


static Str CleanPath(CStr pszPath)
{
   Str psz = strdup(pszPath);
   CleanPath_D(psz);
   return psz;
}


// Return directory name, or NULL if there is no '/' delimiter.
//
static Str PathDir(CStr pszPath)
{
   CStr p = strrchr(pszPath, '/');
   if (!p) {
      return 0;
   }

   return Str_NewSize(pszPath, p - pszPath);
}


// Return file name (same as path if there is no '/' delimiter)
//
static CStr PathFile(CStr pszPath)
{
   CStr p = strrchr(pszPath, '/');
   if (p) {
      return p+1;
   } else {
      return pszPath;
   }
}


static int FileExists(CStr pszFile)
{
   struct stat sb;

   int rv = stat(pszFile, &sb);
   return (rv == 0 && (sb.st_mode & S_IFDIR) == 0);
}


static int FileSize(CStr pszFile)
{
   struct stat sb;

   int rv = stat(pszFile, &sb);
   return (rv == 0 ? (int) sb.st_size : 0);
}


// Read lines from a file into an SList
//
static SList *ReadLines(CStr pszFile)
{
   SList *psl = SList_New();
   SNode **pp = SList_End(psl);
   Str psz;

   GetLine *pgl = GetLine_NewFile(pszFile, 0);

   if (!pgl) {
      Error1("Could not open file", pszFile);
   }

   GETLINE_FORALL(pgl, psz) {
      *pp = SNode_New(strdup(psz));
      pp = &(*pp)->pNext;
   }

   GetLine_Delete(pgl);

   return psl;
}


#if 0
static int CountLines(CStr pszFile)
{
   GetLine *pgl = GetLine_NewFile(pszFile, 0);
   int nLines = 0;
   Str psz;

   if (pgl) {
      GETLINE_FORALL(pgl, psz) {
         ++nLines;
      }
      GetLine_Delete(pgl);
   }

   return nLines;
}
#endif


typedef struct {
   int nLines;     // number of lines
   int nBytes;     // number of bytes
   int nScore;     // number of non-blank lines after stripping comments
} Score;


static void ScoreFile(CStr pszFile, Score *pscore)
{
   GetLine *pgl = GetLine_NewFile(pszFile, 0);
   int nLines = 0;
   int nScore = 0;
   Str psz;
   int bInComment = 0;
   int bBlank = 1;         // blank line so far

   if (pgl) {
      GETLINE_FORALL(pgl, psz) {

         if (!bInComment) {
            bBlank = 1;
         }

         ++nLines;

         while (*psz) {

            if (!bInComment) {

               while (CHAR_ISWHITE(*psz))
                  ++psz;

               if (psz[0] == '/' && psz[1] == '*') {
                  bInComment = 1;
                  psz += 2;
               } else if (psz[0] == '/' && psz[1] == '/') {
                  // skip rest of line
                  break;
               } else {
                  if (bBlank) {
                     bBlank = 0;
                     ++nScore;
                  }
                  ++psz;
               }

            } else {

               while (*psz) {
                  if (psz[0] == '*' && psz[1] == '/') {
                     bInComment = 0;
                     psz += 2;
                     break;
                  } else {
                     ++psz;
                  }
               }
            }

         }
      }

      GetLine_Delete(pgl);
   }

   pscore->nBytes = FileSize(pszFile);
   pscore->nLines = nLines;
   pscore->nScore = nScore;
}


static Score * GetScore(Hash *ph, CStr pszFile)
{
   Score *pscore;

   if ( ! Hash_Get(ph, pszFile, (void**)&pscore)) {
      pscore = NEW(Score);
      ScoreFile(pszFile, pscore);
      Hash_Insert(ph, pszFile, (void*)pscore);
   }

   return pscore;
}



//------------------------------------------------------------
// Dependency Generation
//------------------------------------------------------------

#define CACHESEARCHES   // very minor gain on MacOS

typedef struct {
   SList   slDirs;             // search path directory names
   Hash *  phFindCache;        // cache of path searches  (relname -> fullname)
   Hash *  phIncludedCache;    // cache of included files (fullname -> SList*)
   Hash *  phWhoIncluded;      // tracks nesting (fullname -> who included it)
} Deps;

static Deps *Dep_New(void)
{
   Deps *me = NEW(Deps);

   ZEROPTR(me);
   me->phIncludedCache = Hash_New();
   me->phWhoIncluded = Hash_New();
#ifdef CACHESEARCHES
   me->phFindCache = Hash_New();
#endif
   return me;
}

static void Dep_AddIncludeDir(Deps *me, CStr pszDir)
{
   SList_Append(&me->slDirs, pszDir);
}


// Look for an include directive, returning the referenced name if
// there is one, or 0 if the line does not contain a valid include.
// Throws Error() if a syntax error is detected.
//
// The returned "include" value is in one of the following forms:
//
//   <filename    : for #include <filename> directives
//   "filename    : for #include "filename" directives
//
static Str ScanInclude(CStr pszLine)
{
   char chEnd;
   CStr pszEnd;
   CStr psz = pszLine;

   psz = Str_SkipWhite(psz);
   if (*psz == '#') {
      psz = Str_SkipWhite(psz+1);
      if (Str_Begins("include", psz)) {
         psz = Str_SkipWhite(psz + 7);
         chEnd = *psz;
         if (chEnd == '<') {
            chEnd = '>';
         } else if (chEnd != '"') {
            // perhaps "#include SYMBOL"
            if (gbWarnMissing) {
               fprintf(stderr, "NOT UNDERSTOOD: %s\n", pszLine);
            }
            return 0;
         }

         pszEnd = strchr(psz+1, chEnd);
         if (!pszEnd || pszEnd == psz+1) {
            fprintf(stderr, "NOT UNDERSTOOD: %s\n", pszLine);
            Error("Invalid #include syntax");
         }

         return Str_NewSize(psz, pszEnd-psz);
      }
   }
   return 0;
}

// Return includes from all lines in pgl.
//
static SList *ReadIncludeLines(GetLine *pgl)
{
   SList *pfiles = SList_New();
   Str psz;

   GETLINE_FORALL(pgl, psz) {
      Str pszFile = ScanInclude(psz);
      if (pszFile) {
         SList_Append(pfiles, pszFile);
      }
   }

   return pfiles;
}


static SList *ReadIncludes(CStr pszFile, int bRequire)
{
   SList *plIncs;
   GetLine *pgl = GetLine_NewFile(pszFile, 1);
   if (!pgl) {
      if (bRequire) {
         Error1("CANNOT READ FILE", pszFile);
      }
      return 0;
   }
   plIncs = ReadIncludeLines(pgl);
   GetLine_Delete(pgl);
   return plIncs;
}


// Find an include file's "complete path", given the home directory of
// the including file and the include path.
//
// The returned value is not necessarily an absolute path.  It is
// composed with the home directory or an include directive, either of
// which may be absolute.
//
// Returns 0 if the file is not found.
//
static CStr Dep_FindIncludedFile(Deps *pdc, CStr pszInc, CStr pszDir)
{
   char chType = pszInc[0];
   CStr pszFile = pszInc+1;
   SNode *p;
   Str pszFound;

   if (chType == '\"') {
      Str pszLoc = MakePath(pszDir, pszFile);
      if (FileExists(pszLoc)) {
         CleanPath_D(pszLoc);
         return pszLoc;
      }
   }

   pszFound = 0;
#ifdef CACHESEARCHES
   if ( Hash_Get(pdc->phFindCache, pszFile, (void**)&pszFound))
      return pszFound;
#endif

   SLIST_FORALL(&pdc->slDirs, p) {
      Str pszLoc = MakePath(p->psz, pszFile);
      if (FileExists(pszLoc)) {
         CleanPath_D(pszLoc);
         pszFound = pszLoc;
         break;
      }
   }

#ifdef CACHESEARCHES
   Hash_Insert(pdc->phFindCache, pszFile, pszFound);
#endif

   return pszFound;
}


#define CONST_CAST(Type)  (Type) (uintptr_t) (const Type)

// Get the complete paths for included files, searching the home
// directory and/or the include path.
//
//   bMustExist : If true, pszFile must exist or program will abort.
//
static SList *Dep_GetIncludedFiles(Deps *pdc, CStr pszFile, int bMustExist)
{
   SList *pslPaths;
   SNode *p;

   if ( ! Hash_Get(pdc->phIncludedCache, pszFile, (void**)&pslPaths)) {

      char *pszDir = PathDir(pszFile);
      SList *plIncs = ReadIncludes(pszFile, bMustExist);

      pslPaths = SList_New();

      SLIST_FORALL(plIncs, p) {
         CStr pszInc = p->psz;
         CStr pszAbs = Dep_FindIncludedFile(pdc, pszInc, pszDir);
         if (pszAbs) {
            SList_AppendUnique(pslPaths, pszAbs);

            if (!Hash_Find(pdc->phWhoIncluded, pszAbs)) {
               Hash_Insert(pdc->phWhoIncluded, pszAbs, (void*)CONST_CAST(Str)(pszFile));
            }

         } else if (gbWarnMissing) {
            CStr psz = pszFile;
            fprintf(stderr, "NOT FOUND: %s%c\n", pszInc, (pszInc[0]=='<'?'>':'"'));
            do {
               fprintf(stderr, "  Included by: %s\n", psz);
            } while (Hash_Get(pdc->phWhoIncluded, psz, (void**)&psz));
         }
      }

      Hash_Insert(pdc->phIncludedCache, pszFile, (void*)pslPaths);
   }

   return pslPaths;
}


// Get all dependencies (recursively descending included files)
//
static SList *Dep_GetDeps(Deps *pdc, CStr pszFile)
{
   SList *plDeps = Dep_GetIncludedFiles(pdc, pszFile, 1);
   SNode *p, *psub;

   SLIST_FORALL(plDeps, p) {
      SList *plSub = Dep_GetIncludedFiles(pdc, p->psz, 0);

      SLIST_FORALL(plSub, psub) {
         SList_AppendUnique(plDeps, psub->psz);
      }
   }

   return plDeps;
}


// Return object file name for a given source file
//
static CStr GetObjectName(CStr pszFile)
{
   CStr pszOut = pszFile;

   if (gbObjDir) {
      // concatenate & change extension to .o
      CStr pszName = PathFile(pszFile);
      CStr pszExt = strrchr(pszFile, '.');

      if (pszExt) {
         pszName = Str_NewSize(pszName, pszExt - pszName);
      }

      pszOut = Str_Cat3(gpszObject, pszName, ".o");

   } else if (gpszObject) {
      pszOut = gpszObject;
   }

   if (gbStripPath) {
      pszOut = PathFile(pszOut);
   }

   return pszOut;
}


static void PrintScore(CStr pszFile, SList *plDeps)
{
   Score tot = { 0, 0, 0 };
   int nFiles = 0;
   Hash *ph = Hash_New();
   char chDelim = ' ';
   SNode *p;
   Score *pscore;
   int bPrintDelim = 0;
   char ch;

   CStr pszFields = gpszFields;
   if (pszFields[0] && !Char_IsAlnum(pszFields[0])) {
      chDelim = *pszFields++;
   }
   if ( ! pszFields[0] ) {
      pszFields = "FBLnbls";
   }

   p = NULL;
   SLIST_FORALL(plDeps, p) {
      pscore = GetScore(ph, p->psz);
      ++nFiles;
      tot.nLines += pscore->nLines;
      tot.nBytes += pscore->nBytes;
      tot.nScore += pscore->nScore;
   }

   pscore = GetScore(ph, pszFile);

   for (; ( ch = *pszFields) != '\0'; ++pszFields) {

      if (bPrintDelim) {
         printf("%c", chDelim);
      }
      bPrintDelim = 1;

      switch (ch) {
      case 'F':
         printf("%s", pszFile);
         break;

      case 'B':
         printf("%d", pscore->nBytes);
         break;

      case 'L':
         printf("%d", pscore->nLines);
         break;

      case 'S':
         printf("%d", pscore->nScore);
         break;

      case 'n':
         printf("%d", nFiles);
         break;

      case 'b':
         printf("%d", tot.nBytes);
         break;

      case 'l':
         printf("%d", tot.nLines);
         break;

      case 's':
         printf("%d", tot.nScore);
         break;

      default:
         fprintf(stderr, "UNKNOWN FIELD: '%c'\n", *pszFields);
         bPrintDelim = 0;
         break;
      }
   }
   printf("\n");
}


static void Dep_Print(Deps *pdc, SList *plFiles)
{
   SNode *pfile, *p;

   SLIST_FORALL(plFiles, pfile) {
      CStr pszFile = pfile->psz;
      CStr pszObj = GetObjectName(pszFile);
      SList *pl = NULL;

      switch (gnScan) {
      case CDEPSCAN_ALL:
         pl = Dep_GetDeps(pdc, pszFile);
         break;

      case CDEPSCAN_NORECURSE:
         pl = Dep_GetIncludedFiles(pdc, pszFile, 1);
         break;

      case CDEPSCAN_NORESOLVE:
         pl = ReadIncludes(pszFile, 1);
         break;
      }

      switch (gnOut) {
      case CDEPOUT_DEPS:
         // simple list of dependencies
         SLIST_FORALL(pl, p) {
            printf("%s\n", p->psz);
         }
         break;

      case CDEPOUT_MAKEPLUS:
         // empty dependency line (so stale dependency files won't break make)
         SLIST_FORALL(pl, p) {
            printf("%s:\n", p->psz);
         }
         // FALLTHROUGH
      case CDEPOUT_MAKE:
         // make-style dependency lines
         if (pszFile != pszObj) {
            printf("%s: %s\n", pszObj, pszFile);
         }

         SLIST_FORALL(pl, p) {
            printf("%s: %s\n", pszObj, p->psz);
         }
         break;

      case CDEPOUT_STATS:
         // output stats
         PrintScore(pszFile, pl);
         break;
      }
   }
}


//------------------------------------------------------------
// Test
//------------------------------------------------------------


static void Check(CStr msg, int bTrue)
{
   if (!bTrue) {
      fprintf(stderr, "Test failed: %s\n", msg);
      exit(-1);
   }
   fprintf(stderr, "OK: %s\n", msg);
}


static void Test(void)
{
   GetLine *pgl;
   SList *pfl;
   SNode *pn;
   Str p;

   p = ScanInclude("#include \"foo.h\"");
   Check("si1", Str_EQ(p, "\"foo.h"));

   p = ScanInclude("\t   #   include <xxx.h>");
   Check("si2", Str_EQ(p, "<xxx.h"));

   p = ScanInclude("   #   includ <>");
   Check("si3", p == 0);

   pgl = GetLine_NewBuffer("a\n\nabc");
   Check("gl_nb1", Str_EQ(GetLine_Next(pgl), "a"));
   Check("gl_nb2", Str_EQ(GetLine_Next(pgl), ""));
   Check("gl_nb3", Str_EQ(GetLine_Next(pgl), "abc"));
   Check("gl_nb4", 0 == GetLine_Next(pgl));
   GetLine_Delete(pgl);

   pgl = GetLine_NewBuffer("test\n#include <aa>\n  #include \"x\"\n\n");
   pfl = ReadIncludeLines(pgl);
   pn = pfl->psnFirst;
   Check("ril1", pn && pn->pNext && !pn->pNext->pNext);
   Check("ril2", Str_EQ(pn->psz, "<aa"));
   Check("ril3", Str_EQ(pn->pNext->psz, "\"x"));
   GetLine_Delete(pgl);

   Check("pd1", Str_EQ("a", PathDir("a/b")));
   Check("pd2", Str_EQ("a/b", PathDir("a/b/c")));
   Check("pd2", 0 == PathDir("a"));

   Check("mp1", Str_EQ(MakePath("a", "b"), "a/b"));
   Check("mp2", Str_EQ(MakePath(0, "b"), "b"));
   Check("mp3", Str_EQ(MakePath("a/b", "./c"), "a/b/./c"));

   Check("cp1", Str_EQ(CleanPath("a/b/c"),    "a/b/c"));
   Check("cp2", Str_EQ(CleanPath("./a/b"),    "a/b"));
   Check("cp3", Str_EQ(CleanPath("/./a/b"),   "/a/b"));
   Check("cp4", Str_EQ(CleanPath("a/./b"),    "a/b"));
   Check("cp5", Str_EQ(CleanPath("a/././b"),  "a/b"));
   Check("cp6", Str_EQ(CleanPath("./a/./b"),  "a/b"));
   Check("cp7", Str_EQ(CleanPath("../a/b"),   "../a/b"));
   Check("cp8", Str_EQ(CleanPath("/../a/b"),  "/../a/b"));
   Check("cp9", Str_EQ(CleanPath("a/../c"),   "c"));
   Check("cp10", Str_EQ(CleanPath("a/b/../c"),    "a/c"));
   Check("cp11", Str_EQ(CleanPath("a/b/../../c"), "c"));
   Check("cp12", Str_EQ(CleanPath("../../c"), "../../c"));
   Check("cp13", Str_EQ(CleanPath("a/../../c"), "../c"));

   printf("Tests completed.\n");
}


static void Usage()
{
   printf
      ("Usage:  cdep [option | filename]...\n"
       "\n"
       "Filenames specify source files to scan for dependencies.\n"
       "\n"
       "Options:\n"
       "    -M         : Output dependency lines in 'make' format.\n"
       "    -M+        : Like -M, but includes an additional empty dependency\n"
       "                 line for each included file.  This allows 'make' to\n"
       "                 proceed when the included file does not exist (which\n"
       "                 can occur when dependency files are stale).\n"
       "    -1         : Output simple list of included files.\n"
       "    -S<d><f>   : Output statistics.  <d> and <f> are optional.\n"
       "                 Characters in <f> denote fields:\n"
       "                    'F' = source file name\n"
       "                    'B' = source file size in bytes\n"
       "                    'L' = source file size in lines\n"
       "                    'S' = source file score (lines not blank or comments)\n"
       "                    'n' = number of included files\n"
       "                    'b' = total bytes in included files\n"
       "                    'l' = total lines in included files\n"
       "                    's' = total score for included files\n"
       "                 Default for <f> is 'FBLnbls'.  <d> is a non-alphanumeric\n"
       "                 separator character; default is space.\n"
       "\n"
       "    -I<dir>    : Add <dir> to include search path.\n"
       "    -I <dir>   : Same as -I<dir>.\n"
       "    -o <obj>   : Specify name for object file (LHS of dependency line).\n"
       "    -o <dir/>  : A trailing slash specifies a directory for objects.\n"
       "                 Object names are contructed from source names by\n"
       "                 replacing the extension with '.o'.\n"
       "    -f <file>  : Read file names or -I<dir> directives from <file>.\n"
       "    -i <incs>  : Read list of include directories from <incs>.\n"
       "    -w         : Show warnings.\n"
       "    -n         : Do not recurse into included files.\n"
       "    -s         : Strip path from source/object file name in output.\n"
       "    -x...      : Diagnostic switches (see source code).\n"
       "\n"
       "Default output mode = -M+\n"
       );
}


int main(int argc, char **argv)
{
   SList slFiles = {0};
   Deps *pdc = Dep_New();
   SNode *p;
   ARGV_DECLS;
   char *psz;
   SList sl;

   if (argc == 1) {
      fprintf(stderr, "cdep: nothing to do; try -h for help\n");
      return 0;
   }

   ARGV_FORALL(argv+1, psz) {
      if (psz[0] == '-') {
         switch(psz[1]) {

            // -M : output make-style dependency lines
         case 'M':
            if (psz[2] == '\0') {
               gnOut = CDEPOUT_MAKE;
            } else if (Str_EQ(psz+2, "+")) {
               gnOut = CDEPOUT_MAKEPLUS;
            } else {
               Error1("Bad option", psz);
            }
            break;

            // -Iincludedir : add dir to include search path
         case 'I':
            if (psz[2] != '\0') {
               psz += 2;
            } else {
               psz = ARGV_INDEX(1);
               Require(psz != 0, "-I without directory");
               ARGV_SKIP(1);
            }
            Dep_AddIncludeDir(pdc, psz);
            break;

            // -f namesfile   : read file names from 'namesfile'
         case 'f':
            Require(psz[2] == '\0' && ARGV_INDEX(1), "Bad -f option");
            psz = ARGV_INDEX(1);
            SLIST_FORALL(ReadLines(psz), p) {
               CStr pszLine = Str_SkipWhite(p->psz);

               if (Str_Begins("-I", pszLine)) {
                  SList_Append(&pdc->slDirs, Str_SkipWhite(pszLine+2));
               } else if (pszLine[0]) {
                  SList_Append(&slFiles, pszLine);
               }
            }

            ARGV_SKIP(1);
            break;

            // -i incsfile   : read include dirs from 'incsfile'
         case 'i':
            Require(psz[2] == '\0' && ARGV_INDEX(1), "Bad -i option");
            psz = ARGV_INDEX(1);
            SList_AppendList(&pdc->slDirs, ReadLines(psz));
            ARGV_SKIP(1);
            break;

            // -o outfile   : specifies output object file or directory
            //                (trailing slash denotes directory)
         case 'o':
            Require(psz[2] == '\0' && ARGV_INDEX(1), "Bad -o option");
            gpszObject = ARGV_INDEX(1);
            gbObjDir = (gpszObject && gpszObject[0] && Str_End(gpszObject)[-1] == '/');
            ARGV_SKIP(1);
            break;

            // -w   : show warnings
         case 'w':
            Require(psz[2] == '\0',  "Bad -w option");
            gbWarnMissing = 1;              // warn about non-existent files
            break;

            // -h   : help
         case 'h':
            Usage();
            break;

            // -1 : output dependency files only (not make-style lines)
         case '1':
            Require(psz[2] == '\0', "Bad -1 option");
            gnOut = CDEPOUT_DEPS;
            break;

            // -S : output dependency statistics
         case 'S':
            gnOut = CDEPOUT_STATS;
            gpszFields = psz+2;
            break;

            // -s : strip path from file name
         case 's':
            Require(psz[2] == '\0', "Bad -s option");
            gbStripPath = 1;
            break;


            // -n   : no recurse; immediate dependencies
         case 'n':
            Require(psz[2] == '\0', "Bad -n option");
            gnScan = CDEPSCAN_NORECURSE;
            break;

            //----   diagnostic options   ----

         case 'x':
            ++psz;
            switch (psz[1]) {

               // -xi  : include directives only
            case 'i':
               gnScan = CDEPSCAN_NORESOLVE;
               break;

               // -xt   : run unit tests
            case 't':
               Test();
               break;

               // -xefile   or  -xe metafile  : show files that exist
            case 'e':
               ZEROREC(sl);

               Require(psz[2] || ARGV_INDEX(1), "Expected file after -xs");
               if (psz[2]) {
                  SList_Append(&sl, psz+2);
               } else {
                  sl = *ReadLines(ARGV_INDEX(1));
                  ARGV_SKIP(1);
               }

               SLIST_FORALL(&sl, p) {
                  if (FileExists(p->psz)) {
                     puts(p->psz);
                  }
               }
               break;
            }
            break;

         default:
            Error1("Unknown option", psz);
         }
      } else {
         SList_Append(&slFiles, psz);
      }
   }

   Dep_Print(pdc, &slFiles);

   return 0;
}
