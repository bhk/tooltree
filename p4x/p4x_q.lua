-- p4x_q : test p4x
--
-- By default, this loads and calls 'p4x.lua' directly, but it will test
-- a compiled executable form of p4x if given a "p4x=<exe>" argument.
-- These tests rely on 'simp4'.  The command to use to invoke simp4 can be
-- specified via the SIMP4 env var, or "simp4=<exe>" on the command line.
--
-- This test does most of its work in a directory other than the current
-- directory, which unfortunately complicates things:
--  * We must construct absolute paths for invoked exes (simp4, p4x)
--
-- For debugging, use verbose mode:
--  * "p4x_q_v=1 make" runs automated tests in verbose mode
--  * <tmp>/p4xlog shows the simp4 output p4x sees
--
-- Command-line arguments:
--    p4x=<exe>    : executable to test (optional)
--    simp4=<exe>  : simp4 command [alternative: $SIMP4 ]
--    tmp=<tmpdir> : temp dir to use; defaults to $OUTDIR
--    v=1          : verbose [alternative: $p4x_q_v ]
--
local qt = require "qtest"
local xpfs = require "xpfs"
local F = require "lfsu"
local TE = require "testexe"

local eq, match = qt.eq, qt.match

local bWin = (xpfs.getcwd():sub(2,2) == ":")

local function stringToPattern(str)
   return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

----------------------------------------------------------------
-- process command line options
----------------------------------------------------------------

local vars = {}
for _,a in ipairs(arg) do
   local name,val = a:match("(.-)=(.*)")
   if not name then error("args take form: name=value") end
   vars[name] = val
end

vars.v = vars.v or os.getenv("p4x_q_v")

local function verbose(...)
   if vars.v then qt.printf(...) end
end

local function absify(name, default, isexe)
   local val = vars[name] or default
   if val then
      val = F.abspath( val )
      if isexe and bWin then
         val = val:gsub("/", "\\")
      end
      vars[name] = val
      verbose("%s = %s\n", name, val)
   end
end

absify("p4x", nil, true)
absify("simp4", os.getenv("SIMP4"), true)
absify("tmp", os.getenv("OUTDIR"))
assert(vars.tmp)

local workdir = vars.tmp .. "/PT"
verbose("** p4x_q workdir = %s\n", workdir)

----------------------------------------------------------------
-- file system utilities
----------------------------------------------------------------

-- Read descriptions of directory tree
--   file =>  up to 8 bytes of content, prefixed with "*" if writable
--   dir  =>  { name = <tree>, ... }
--
local function readTree(node)
   local st = xpfs.stat(node, "kp")
   if st and st.kind ~= "d" then
      return (st.perm:sub(2,2)=="w" and "*" or "") .. F.read(node):sub(1,8)
   end
   -- directory
   local t = {}
   for _, file in ipairs( xpfs.dir(node) ) do
      if file:sub(1,1) ~= "." then
         local abs = node .."/" .. file
         t[file] = readTree(abs)
      end
   end
   return t
end

-- Create tree of files/directories described in tree
--
local function writeTree(tree, loc)
   if type(tree) == "table" then
      xpfs.mkdir(loc)
      for file,val in pairs(tree) do
         writeTree(val, loc .. "/" .. file)
      end
   else
      local mode, data = tree:match("(%*?)(.*)")
      F.write(loc, data)
      if mode ~= "*" then
         xpfs.chmod(loc, "-w")
      end
   end
end

local function expectTree(tree)
   return eq(tree, readTree("."))
end

----------------------------------------------------------------
-- Construct environment for invoking p4x
----------------------------------------------------------------

local e = TE:new(vars.p4x or "@p4x.lua", vars.v)
local simdat, simdatOut

-- Invoke p4x command
--
local function p4x(args, cfg)
   F.write(".simdat", qt.format("return %Q", assert(simdat)))
   cfg = cfg or ".p4xt"
   e:exec("--config=" .. cfg .." " .. (vars.v and "-v " or "") .. args)
   simdatOut = nil -- invalidate
end

local function getsimdat()
   simdatOut = simdatOut or assert(loadfile(".simdat"))()
   return simdatOut
end

local function expectLog( matches, pat )
   return eq( TE.sort(matches), TE.sort(TE.grep(getsimdat().log, pat)))
end

local startdir = xpfs.getcwd()
F.rm_rf(workdir)
xpfs.mkdir(workdir)
xpfs.chdir(workdir)

local configFile = [==[
  statusView = "...\n-.*\n"
  scrubView  = "...\n-.*\n"
  p4Command  = [[SIMP4]]
]==]
if vars.v then
  configFile = configFile.. '  log = "../p4xlog"\n'
end
configFile = configFile:gsub("SIMP4", vars.simp4)

F.write(".p4xt", configFile)

----------------------------------------------------------------
--  simp4 tests
----------------------------------------------------------------

-- This describes the initial state of the directory tree.
--
local initialTree = {
   A = "A",
   B = "*B",  -- "*" => writable
   c = "c",
   d = "*d",
   f = { e = "*e" },
   g = "*g",
   n = "nn",
   x = { y = { z = "*z" } }
}

-- simdat = SIMP4's notion of the repository & workspace
--
simdat = {
   files = {
      -- file name -> contents
      ["//depot/a"] = "a=",
      ["//depot/b"] = "b=",
      ["//depot/c"] = "c=",
      ["//depot/d/e"] = "d/e=",
      ["//depot/f"] = "f=",
      ["//depot/g"] = "g=",
      ["//depot/n"] = "n",
      ["//depot/t/u/v"] = "t/u/v=",
   },
   actions = {
      ["//depot/c"] = "edit",
      ["//depot/h"] = "add",
   },
   haves = {},

   -- SIMP4 assumes relative paths (e.g. "...") are relative to this
   depotCWD = "//depot",

   -- client is used to map depot locations to local paths
   client = {
      Client = "C",
      Root = xpfs.getcwd(),
      View = { "//depot/... //C/..." }
   }
}

-- Initialize haves[]
for k in pairs(simdat.files) do
   simdat.haves[k] = 1
end


----------------------------------------------------------------
-- Initialize client subtree
----------------------------------------------------------------

writeTree(initialTree, ".")
local s

--------------------------------
-- test version
--------------------------------

p4x "version"
e:expect "p4x [%d%?]%.[%d%?]"

--------------------------------
-- test find
--------------------------------

p4x "find ..."
eq( {"A", "B", "c", "d", "f/e", "g", "n", "x/y/z"},
        e.sort(e:filter"^%./([^%.].*)") )

p4x "find ...[cde]"
eq( { "c", "d", "f/e" }, e.sort( e:filter "^%./(.*)" ) )

--------------------------------
-- test status
--------------------------------

p4x "status"
expectTree( initialTree )
eq( { "! a","! b","! d/e","! f","! t/u/v",
          "? A","? B","? d","? f/e","? x/y/z","E c","M g","a h" },
        e.sort(e:filter("([^#] .*)")))

p4x "status --all"
eq( { "! a","! b","! d/e","! f","! t/u/v",
          "? A","? B","? d","? f/e","? x/y/z","E c","M g","a h" },
        e.sort(e:filter("([^#] [^%.].*)")) )

--------------------------------
-- test addremove
--------------------------------

p4x "addremove"
expectTree( initialTree )
expectLog( {}, "add (.*)" )
expectLog( {}, "delete (.*)" )
qt.match(e.out, "Use .--force")

p4x "addremove --force"
expectTree( initialTree )
expectLog( {"A","B","d","f/e","x/y/z"}, "add %./(.*)" )
expectLog( {"a","b","d/e","f","t/u/v"}, "delete %./(.*)" )
expectLog( {"g"}, "edit %./(.*)" )
expectLog( {"./h", "-a ./..."}, "revert (.*)" )
eq("B", F.read("B"))   -- should have retained new (writable) file contents

F.write(".p4x2", configFile .. "\naddremoveNoConfirm=true\n")
p4x("addremove --new", ".p4x2")
assert( not e.out:match("Use .--force") )
expectTree( initialTree )
expectLog( {"A","B","d","f/e","x/y/z"}, "add %./(.*)" )
expectLog( {"a","b","d/e","f","t/u/v"}, "delete %./(.*)" )
expectLog( {"g","n"}, "edit %./(.*)" )


--------------------------------
-- test logging
--------------------------------

p4x "status . --log=xx"
local xx = F.read("xx")
match(xx, "%%.-simp4.-%>")
match(xx, "\n | info1: action edit")
match(xx, "M g\n")

os.remove("xx")

--------------------------------
-- test scrub
--------------------------------

p4x "scrub"
expectTree( initialTree ) -- no change without "--force"

assert(xpfs.mkdir("f/aa"))  -- another bogus dir not in depot
p4x "scrub --force"
expectTree {
   a = "a=",                     -- file name case changed  (replaces A)
   b = "b=",                     -- file name case changed  (replaces B)
   g = "g=",                     -- was writable; replaced with server version
   f = "f=",                     -- directory -> file
   c = "c",                      -- unchanged since it was read-only, unedited
   d = { e = "d/e=" },           -- d: file -> directory
   t = { u = { v = "t/u/v=" } }, -- t: new directory
   n = "nn",                     -- n: not writable, but modified
}
expectLog( {"./h"}, "revert ([^\n]*)" )

-- scrub should recognize nothing needs to be done now
--     (e.g. local dir t/u is not in repo but implied by t/u/v)
simdat = getsimdat()
p4x "scrub --force"
eq("", e.out)

--------------------------------
-- test ls
--------------------------------

p4x "ls"
e:expect(stringToPattern[[
d---------                 d
d---------                 t
-r--------  2              a
-r--------  2              b
-rw-------  2              c
-r--------  2              f
-r--------  2              g
-r--------  1              n
]])

p4x "ls //depot/t"
e:expect(stringToPattern[[
d--------- u
]])
print("p4x ok")

--------------------------------
-- done
--------------------------------
xpfs.chdir(startdir)
F.rm_rf(workdir)
