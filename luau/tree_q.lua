local qt = require "qtest"

----------------------------------------------------------------
-- A test implementation of xpfs
----------------------------------------------------------------
local xpfs = {}
package.loaded.xpfs = xpfs

local xpfsFiles = {
   ["/"] = "drwx",
   ["/a"] = "drwx",
   ["/a/b"] = "-rwx",
   ["/a/bb"] = "-rwx",
   ["/a/c"] = "-rwx",
   ["/a/f"] = "-rwx",
   ["/a/d"] = "drwx",
   ["/a/d/a"] = "-rwx",
   ["/a/x"] = "drwx",
   ["/a/x/a"] = "-rwx",
   ["/b"] = "drwx",
   ["/b/x"] = "drwx",
   ["/b/x/a"] = "-rwx",
   ["/b/x/b"] = "-rwx",
   ["/b/x/c"] = "-rwx",
}

function xpfs.dir (name)
   if name:sub(-1,-1) ~= "/" then name = name .. "/" end
   local res = {}
   for k,v in pairs(xpfsFiles) do
      if k:sub(1,#name) == name and k ~= name then
         local fname = k:sub(#name+1)
         if not fname:match("/") then
            -- qt.printf("dir(%s) : %s\n", name, fname)
            table.insert(res, fname)
         end
      end
   end
   return res
end

function xpfs.stat(name, mask)
   local ls = xpfsFiles[name]
   return {
      kind = ls:match("^d") and "d" or "f",
      perm = ls:sub(2),
   }
end

function xpfs.getcwd()
   return "/"
end

----------------------------------------------------------------
-- test tree.el
----------------------------------------------------------------
local tree = require "tree"
local T = qt.tests


function T.rtrim()
   local rtrim = tree._.rtrim
   qt.eq("ab  c", rtrim("ab  c    "))
   qt.eq("ab  c", rtrim("ab  c"))
   qt.eq(" b  c", rtrim(" b  c"))
end

function T.matchFile()
   local matchFile = tree.matchFile

   local function f(pat,str,result)
      return qt.eq(result, matchFile(pat)(str))
   end

   local function ferr(pat, errpat)
      local succ, result = pcall(matchFile, pat)
      qt._eq(false, succ, 2)
      if not result:match(errpat) then
         error("assertion failed!", 2)
      end
   end

   f(".", ".", true)
   f(".", "a", false)
   f("a*", "a", true)
   f("a*", "ab", true)
   f("a*", "a/b", false)

   f("a/?", "a/b", true)
   f("a/?", "a/bc", false)

   f("a...", "a", true)
   f("a....", "a", false)
   f("a.....", "a", false)
   f("a......", "a", true)
   f("a...", "ab/c", true)
   f("a...", "a/b", true)
   f("a...", "b", false)
   f("a...b", "ab", true)
   f("a...b", "a/b", true)
   f("a...b", "a/c/b", true)
   f("a...b", "a/bc", false)

   f("a...*", "a", true)

   f("%^$+.-", "%^$+.-", true)
   f("%^$+.-", "%^$+.-a", false)
   f("%^$+.-", "a%^$+.-", false)

   f("a[bc]d", "abd", true)
   f("a[bc]d", "acd", true)
   f("a[bc]d", "aed", false)
   f("a[bc]d", "ac", false)

   f("a()b", "ab", true)
   f("a()b", "a", false)
   f("a(b|c|d)e", "abe", true)
   f("a(b|c|d)e", "ace", true)
   f("a(b|c|d)e", "ade", true)
   f("a(b|c|d)e", "aee", false)
   f("a(b|c|d)e", "ae", false)
   f("a(b|c|)e", "ae", true)

   f("a(b|c)d(e|f)g", "abdfg", true)
   f("a(b|c)d(e|f)g", "acdeg", true)
   f("a(b|c)d(e|f)g", "adeg", false)
   f("a(b|c)d(e|f)g", "acdg", false)

   f("c:/...", "c:/a", true)
   f("c:/...", "c:/",  true)

--   ferr("a(b", "^:: matchFile: unbalanced .* %[a%(b%]$")
--   ferr("a)b", "^:: matchFile: unbalanced .* %[a%)b%]$")
--   ferr("a[b", "^:: matchFile: unbalanced .* %[a%[b%]$")
--   ferr("a]b", "^:: matchFile: unbalanced .* %[a%]b%]$")
--   ferr("a[(]b", "^:: matchFile: invalid .* %[a%[%(%]b%]$")
end


function T.dirAnyPatterns()
   local function p(pat, tbl)
      return qt.eq(tbl, tree._.dirAnyPatterns(pat))
   end

   p("/a",     {"/"} )
   p("/a/",    {"/", "/a"} )
   p("/a/",    {"/", "/a"} )
   p("/a/b",   {"/", "/a"} )
   p("/a/b/c", {"/", "/a", "/a/b"} )
   p("/a/*",   {"/", "/a"} )
   p("/a/...", {"/", "/a", "/a/..."} )
end

function T.matchDir()
   local matchDirAll = tree.matchDirAll
   local matchDirAny = tree.matchDirAny

   qt.eq(false, matchDirAll("a....", "a")())

   local function d(pat, dir, cat)
      local b = matchDirAll(pat)(dir)
      qt._eq(cat=="all", b, 2)

      local b = matchDirAny(pat)(dir)
      qt._eq(cat~="none", b, 2)
   end

   d("/a/...", "/a/b/c",   "all")

   d("/a/b/...", "/a/b",   "all")
   d("/a/b/...", "/a/b/c", "all")
   d("/a/b/...", "/a",     "some")
   d("/a/...",   "/aa",    "none")
   d("/a...",    "/a",     "all")
   d("/a....",   "/a",     "some")  -- same as "a...[.]"
   d("/a...",    "/ab",    "all")
   d("/a...",    "/ab/c",  "all")
   d("/a...",    "/b",     "none")
   d("/a...b",   "/a",     "some")
   d("/a*",      "/a",     "none")
   d("/a",       "/a",     "none")
   d("/a/b",    "/a",    "some")
   d("/a/b",    "/",     "some")
   d("/a/b",    "/a/b",  "none")
   d("/*/b",    "/a",    "some")
   d("/*/b",    "/a/b",  "none")
   d("/*/c/...","/a/b",  "none")
   d("/*/c/...","",      "none")
   d("/[ab]/...","/a",   "all")
   d("/[ab]/...","/c",   "none")

   d("/a...",    "/",    "some")
   d("/...",     "/",    "all")
   d("/*...",    "/",    "all")

   d("c:/a...",  "c:/",  "some")
   d("c:/a...",  "c:/a", "all")
   d("c:/a/...", "c:/a", "all")
   d("c:/a...",  "c:/b", "none")

   -- imprecise, conservative dir matching is suboptimal but ok
   d("/...*",    "/",    "some")  -- NOT IDEAL
   d("/...(a|)", "/",    "some")  -- NOT IDEAL
end

function T.covers()
   local covers = tree._.covers

   assert( covers("/a", "/a/b") )
   assert( not covers("/a/b", "/a/c") )
   assert( not covers("/ab", "/abc") )
end

function T.parseSpec()
   local parseSpec = tree.parseSpec

   local s = parseSpec("/a/b")
   qt.eq(true, s.ftest("/a/b"))
   qt.eq(false, s.dtest("/a/b"))

   local s = parseSpec([[
/a/b
/a/c
d
-/a/c
                    ]], "/a")

   qt.eq(true, s.ftest("/a/b"))
   qt.eq(false, s.ftest("/a/c"))
   qt.eq(true, s.ftest("/a/d"))
   qt.eq(true, s.dtest("/a"))

   s = parseSpec("...", "/a/b")
   qt.eq(true, s.dtest("/a/b"))
   qt.eq(true, s.dtest("/a"))

   s = parseSpec("...\n-...c\n-...x/...", "/")
   qt.eq(true, s.ftest("/a/b"))
   qt.eq(false, s.ftest("/a/b/c"))
   qt.eq(true, s.ftest("/a/b/c/x"))
   qt.eq(false, s.ftest("/a/b/c/x/y"))

   s = parseSpec("...\n-x...\n&...b", "/")
   qt.eq(false, s.ftest("/x/b"))
   qt.eq(false, s.ftest("/a/y"))
   qt.eq(true, s.ftest("/a/b"))
   qt.eq(true, s.dtest("/a/y"))
   qt.eq(false, s.dtest("/x/y"))
   qt.eq(false, s.dtest("/x"))
   qt.eq(true, s.dtest("/"))

   -- roots

   s = parseSpec("a/b/...\nc/d/...\na/d/...")
   qt.eq({"/a/b","/a/d","/c/d"}, s.roots)

   s = parseSpec("/a/...\n/b/...\n/...")
   qt.eq({"/"}, s.roots)
end


function T.findx()
   local findx = tree.findx

   local t = findx(
      {"/"},
      { ftest = function (file) return file:sub(-1,-1) ~= 'c' end,
        dtest = function (dir) return dir:sub(-1,-1) ~= 'x' end }
   )

   qt.eq(4, #t)
end

function T.find()
   local find = tree.find
   local o
   local function io_open(fname)
      o.names = o.names .. fname .. ";"
      if o.path and o.path ~= fname then return nil end
      return { read = function (f,a) assert(a=="*a"); return o.result end,
               close = function () end }
   end

   local function testfind()
      -- treespec,  external
      o = {names = "", result = "../a/d/..." }
      local a, d, spec = find("/b", ".XYZ", true)
      qt.eq("/b/.XYZ;", o.names)
      qt.eq({{name="/a/d/a",perm="-rwx"}}, a)
      qt.eq(true, spec ~= nil)
      qt.eq(true, spec.ftest ~= nil)
      qt.eq(true, spec.dtest ~= nil)
      qt.eq(true, spec.ftest("/a/d/file"))
      qt.eq(false, spec.ftest("/a/file"))

      -- treespec, no external
      o = {names = "", result = "../a/d/..." }
      local a = find("/b", ".XYZ", false)
      qt.eq("/b/.XYZ;", o.names)
      qt.eq({}, a)

      -- no treespec
      o = {names = "", result = "../a/d/..." }
      local a = find("/b", false, true)
      qt.eq("", o.names)
      table.sort(a, function (a,b) return a.name > b.name end)
      qt.eq({{name="/b/x/c",perm="-rwx"},{name="/b/x/b",perm="-rwx"},
                 {name="/b/x/a",perm="-rwx"}}, a)

      -- treespec in parent dir
      o = {names = "", result = "b/x/[bc]", path="/.XYZ" }
      local a = find("/b/x", ".XYZ", false)
      qt.eq("/b/x/.XYZ;/b/.XYZ;/.XYZ;", o.names)
      table.sort(a, function (a,b) return a.name > b.name end)
      qt.eq({{name="/b/x/c",perm="-rwx"},{name="/b/x/b",perm="-rwx"}}, a)


   end

   local sav = io.open
   io.open = io_open
   testfind()
   io.open = sav
end


return qt.runTests()
