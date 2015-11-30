local qt = require "qtest"
local futils = require "futils"
local xpfs = require "xpfs"

local T = qt.tests
local eq = qt.eq


local function feq(fu,a,b)
   if fu.eqForm(a) ~= fu.eqForm(b) then
      error("Eqed "..a.." eq "..b, 2)
   end
end
local function fneq(fu,a,b)
   if fu.eqForm(a) == fu.eqForm(b) then
      error("Eqed "..a.." fneq "..b, 2)
   end
end
local function tr(fu,a,b,c)
   return eq(c, fu.resolve(a,b))
end

function T.nixComputeRelPath()
   local function tt(a,b,c)
      return eq(c, futils.nixComputeRelPath(a,b))
   end

   tt("/a/b/c", "/a/b/c/d", "d")
   tt("/a/b/c", "/a/b/c", ".")
   tt("/a/b/c", "/a/b", "..")
   tt("/a/b/c", "/a", "../..")
   tt("/a/b/c", "/a/b/cd", "../cd")

   -- 15-sep-10 : Was behaving oddly when src had a trailing "/" (URI
   -- convention).
   tt("/a/b/c/", "/a/b/c/d", "d")
   tt("/a/b/c/", "/a/b/c", ".")
   tt("/a/b/c/", "/a/b", "..")
end

function T.winComputeRelPath()
   local function tt(a,b,c)
      return eq(c, futils.winComputeRelPath(a,b))
   end

   tt("/a/b/c", "/a/b/c/d", "d")
   tt("/a/b/c", "/a/b/c", ".")
   tt("/a/b/c", "/a/b", "..")
   tt("/a/b/c", "/a", "../..")
   tt("/a/b/c", "/a/b/cd", "../cd")

   tt("/a/b/c/", "/a/b/c/d", "d")
   tt("/a/b/c/", "/a/b/c", ".")
   tt("/a/b/c/", "/a/b", "..")
   tt("/a/b/c/", "/a", "../..")
   tt("/a/b/c/", "/a/b/cd", "../cd")

   tt("c:/a",   "c:/b",  "../b")
   tt("c:/a",   "C:/b",  "../b")
   tt("/a",     "c:/b",  "c:/b")

--   tt("c:/a",   "/b",    "../b")  incorrect test
   tt("a:/a",   "c:/b",  "c:/b")
end

function T.parent(p)
   local parent = futils.parent
   eq("/ab/cd", parent("/ab/cd/ef"))
   eq("/",      parent("/a"))
   eq("/",      parent("/"))
   eq("c:/",    parent("c:/a"))
   eq("c:/",    parent("c:/"))
end


function T.splitPath(p)
   local fw = futils.new("c:/foo")
   local fu = futils.new("/foo")
   local function sptest(f, path, dir, file)
      return eq( {dir,file}, {f.splitPath(path)} )
   end

   sptest(fw, "c:/d/e/f",    "c:/d/e",    "f")
   sptest(fw, "C:\\x\\y\\z", "C:\\x\\y", "z" )
   sptest(fw, "c:\\a",       "c:\\",      "a")
   sptest(fw, "\\a\\b",      "\\a",       "b")
   sptest(fw, "/a/b",        "/a",        "b")

   sptest(fu, "c:\\a",       ".",         "c:\\a")
   sptest(fu, "c:/a",        "c:",        "a")

   sptest(fu, "/a",          "/",         "a")
   sptest(fu, "/...",        "/",         "...")
end

function T.cleanPath()
   local function tcp(a,b)
      return eq(b, futils.cleanPath(a))
   end

   tcp("a/.", "a")
   tcp("/a/.", "/a")
   tcp("a/..", ".")
   tcp("/a/..", "/")
   tcp("a/b/../..", ".")
   tcp("/a/b/../..", "/")
   tcp("a/../..", "..")
   tcp("/a/../..", "/..")

   tcp("./b", "b")
   tcp("/./b", "/b")
   tcp("a/./b", "a/b")
   tcp("/a/./b", "/a/b")

   tcp("a/./././././././b", "a/b")
   tcp("a./b", "a./b")
   tcp("a/.b", "a/.b")

   tcp("a/..", ".")
   tcp("a/b/..", "a")
   tcp("../b", "../b")
   tcp("a/../b", "b")
   tcp("/a/../b", "/b")
   tcp("b/..a", "b/..a")
   tcp("b../a", "b../a")
   tcp("b../..a", "b../..a")
   tcp("b../..a", "b../..a")

   tcp("/..", "/..")
   tcp("a/b/c/d/../../..", "a")
   tcp("a/b/c/d/../../e", "a/b/e")

   tcp("/a/./../b", "/b")
   tcp("./../b", "../b")
   tcp("/a/b/./.././c", "/a/c")

   tcp("a/.././.", ".")
   tcp("a/.../b", "a/.../b")

   tcp("../../a", "../../a")
   tcp("../../../a", "../../../a")
   tcp("a/../../b", "../b")

   tcp("c:/..", ".")   -- odd behavior for odd case in Windows
end


-- UNIX variants


local u = futils.new("/a")

function T.resolve()
   tr(u, "/a", "/a/b",   "/a/b")
   tr(u, "/a", "c:/b",   "/a/c:/b")
   tr(u, "c:/a", "/b",   "/b")
   tr(u, "c:\\a", "/b",   "/b")
end

function T.abspath()
   eq("/a/b", u.abspath("b"))
   eq("/b",   u.abspath("/b"))
   eq("/a/d:/b",   u.abspath("d:/b"))
end

function T.relpath()
   eq("b",      u.relpath("/a/b"))
   eq("b",      u.relpath("b"))
   eq("/c",     u.relpath("/c"))

   local w1 = futils.new("c:/")
   eq("aB",     w1.relpath("c:/aB"))
   eq("aB",     w1.relpath("c:/aB"))

   local w2 = futils.new("c:/a/B")
   eq("Cd",     w2.relpath("c:/a/B/Cd"))
   eq("Cd",     w2.relpath("C:/a/b/Cd"))
end

function T.prettify()
   eq("/A\\b",  u.prettify("/A\\b"))
end

function T.eqForm()
   feq(u, "c:/a",  "c:/a")
   fneq(u, "a",    "A")
   fneq(u, "c:/a", "C:\\A")
   fneq(u, "\\a",  "/A")
   fneq(u, "C:/a", "\\A")
   fneq(u, "/a",   "c:\\A")
end


-- Windows variants


local w = futils.new("c:/a")

function T.resolve()
   tr(w, "c:/a", "b",     "c:/a/b")
   tr(w, "x:/a", "/b",    "x:/b")
   tr(w, "c:/a", "d:/b",  "d:/b")
end

function T.abspath()
   eq("c:/a/b", w.abspath("b"))
   eq("c:/b",   w.abspath("/b"))
   eq("d:/b",   w.abspath("d:/b"))
end

function T.relpath()
   eq("b",      w.relpath("c:/a/b"))
   eq("d:/c",   w.abspath("d:/c"))
end

function T.prettify()
   eq("c:/A/b",  w.prettify("C:\\A\\b"))
end

function T.eqForm()
   feq(w, "c:/a",  "C:\\A")
   feq(w, "\\a",   "/A")
   fneq(w, "C:/a", "\\A")
   fneq(w, "/a",   "c:\\A")
end


-- removeTree
local tmpdir = assert(os.getenv("OUTDIR")) .. "/futils_q"


local function abs(f)
   return tmpdir .. "/" .. f
end


function T.removeTree()
   xpfs.mkdir( tmpdir )
   eq( "d", xpfs.stat(tmpdir, "k").kind )

   for _,name in ipairs { "d", "d/e", "d/e/f" } do
      assert( xpfs.mkdir( abs(name) ) )
   end
   for _,name in ipairs { "a", "d/e/c", "d/e/f/ro" } do
      futils.write( abs(name), "text")
   end
   assert( xpfs.chmod( abs("d/e/f/ro"), "-w") )

   assert( futils.removeTree( tmpdir ) )

   eq(nil, (xpfs.stat(tmpdir)) )  --> does not exist
end


function T.makeParentDir()
   local fu = futils.new()

   xpfs.mkdir( tmpdir )
   eq( "d", xpfs.stat(tmpdir, "k").kind )

   fu.write( abs("foo"), "footext")

   local e,m = fu.makeParentDir( abs("a/b/file") )
   assert(e)
   eq( "d", xpfs.stat( abs("a/b"), "k").kind )
   eq( nil, (xpfs.stat( abs("a/b/file"))) )

   local e,m = fu.makeParentDir( abs("foo/a") )
   assert(not e)
   qt.match(m, "could not create")
   eq("footext", fu.read( abs("foo"), "footext"))
end


return qt.runTests()
