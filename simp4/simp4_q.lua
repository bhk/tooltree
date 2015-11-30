-- Usage:  lua simp4_q.lua  [simp4cmd]
-- Set env var simp4_q_v=1 for verbose output.
--
local qt = require "qtest"
local TE = require "testexe"
local xpfs = require "xpfs"
local F = require "lfsu"

-- work out of OBJ_DIR to allow parallel builds

local eq = qt.eq

local simp4Cmd = arg[1] and F.abspath(arg[1]) or "@simp4.lua"
local tmp = assert(os.getenv("OUTDIR"))
local e = TE:new(simp4Cmd, os.getenv("simp4_q_v"))
xpfs.chdir(tmp)

local function clone(t)
   if type(t) ~= "table" then return t end
   local t2 = {}
   for k,v in pairs(t) do
      t2[clone(k)]= clone(v)
   end
   return t2
end

----------------------------------------------------------------
-- simp4 harness
----------------------------------------------------------------

local simdatStart = {

   ----------------
   -- Server state
   ----------------

   -- files : the files in the repository and their contents

   files = {
      ["//depot/a/file"] = "some text",
      ["//depot/b/x"] = "=b/x",
      ["//depot/c/x"] = "=c/x",
      ["//dx/y"] = "=y",
   },

   -- info : array of lines of text to return in response to 'p4 info'
   info = { "Server address: p4srvr.com:1666" },

   brokenPrintS = false,  -- see simp4.lua

   clients = {},

   ----------------
   -- Client state
   ----------------

   actions = {
      ["//depot/a/file"] = "edit",
      ["//depot/a/newfile"] = "add",
   },

   -- haves: file -> version   (read/written by sync)
   haves = {
      ["//depot/a/file"] = 1
   },

   -- depotCWD: this is used whenever SIMP4 is passed a relative filespec.
   -- This must be a depot dir (e.g. "//depot/x") to be treated as cwd.
   -- NOTE: If this does not match the depot location implied by the
   -- simdat.client and actual CWD, be prepared for confusing results.

   depotCWD = "//dx",

   -- "client" : user-visible settings accessed via "p4 client".  The client
   -- subcommand uses this, and 'sync' uses it to map depot paths to local
   -- paths.

   client = {
      Root = "/tmp",
      Client = "C",
      View = {
         "//depot/... //C/s4/...",
         "-//depot/a/x/... //C/s4/a/x/...",
         "-//depot/c/... //C/s4/c/...",
         "//dx/... //C/s4/...",
      }
   },
}

local simdat = clone(simdatStart)
local simout

local function simp4(args)
   -- write out simdat
   local f = io.open(".simdat", "w")
   f:write("return " .. qt.describe(simdat))
   f:close()
   -- run simp4 (e.out holds simp4 output)
   e(args)
   simout = assert(loadfile(".simdat"))()
   simdat = clone(simdatStart)
end

local function lookfor(str)
   e:expect(str, 2)
end

-- construct a pattern that matches string str
local function pquote(str)
   return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"):gsub("%z", "%%z"))
end


----------------------------------------------------------------
-- simp4 tests
----------------------------------------------------------------

simp4 "-V"
lookfor [[
^Perforce %- The Fast Software Configuration Management System%.
[%w %.%-]+
Rev. P4/NTX86/2007%.2/122958 %(2007/05/22%)%.
]]

simdat.os = "MACOS104"
simp4 "-V"
lookfor [[
^Perforce %- The Fast Software Configuration Management System%.
[%w %.%-]+
Rev. P4/MACOS104X86/2007%.2/122958 %(2007/05/22%)%.
]]

simp4 "-s print //depot/a/file"
lookfor [[
text: some text
exit: 0
]]

simp4 "-s dirs //*"
lookfor [[
^info: //depot
info: //dx
exit: 0
$]]

simp4 "dirs //*"
lookfor [[
^//depot
//dx
$]]

simp4 "-s dirs //depot/*"
lookfor [[
^info: //depot/a
info: //depot/b
info: //depot/c
exit: 0
$]]

simp4 "-s dirs //foo/*"
lookfor [[
^error: //foo/.* - no such file%(s%)%.
exit: 0
$]]

simp4 "-s files //...x"
lookfor [[
^info: //depot/b/x
info: //depot/c/x
exit: 0
$]]

simp4 "info"
lookfor [[
^Client name: C
Client root: /tmp
Server address: p4srvr.com:1666
$]]

simp4 "-s info"
lookfor [[
^info: Client name: C
info: Client root: /tmp
info: Server address: p4srvr.com:1666
exit: 0
$]]

simp4 "print //depot/a/file"
lookfor [[
^//depot/a/file.-
some text
$]]

simp4 "-s print //depot/a/file"
lookfor [[
^info: //depot/a/file %- .-
text: some text
exit: 0
$]]

simp4 "-s print -q //...x"
lookfor [[
^text: =b/x
text: =c/x
exit: 0
$]]

simp4 "client -o"
lookfor [[
View:
	//depot/... //C/s4/..%.
	%-//depot/a/x/... //C/s4/a/x/..%.
	%-//depot/c/... //C/s4/c/..%.
	//dx/... //C/s4/..%.
]]

simp4 "-s client -o"
lookfor [[
info: Client:	C
info:.
.*info: View:
info: 	//depot/%.%.%. //C/s4/%.%.%.
info: 	%-//depot/a/x/%.%.%. //C/s4/a/x/%.%.%.
info: 	%-//depot/c/%.%.%. //C/s4/c/%.%.%.
info: 	//dx/%.%.%. //C/s4/%.%.%.
]]
eq(1, #simout.log)
qt.match(simout.log[1], "%-s client %-o")


-- ** "client -i" accepts valid client

e.stdin = [[
Root:	/tmptmp

Client:	C

View:
	//depot/a/... //C/x/...
	"//depot/b /..." //C/y/...
]]
simp4 "-s client -i"
lookfor "^exit: 0"
eq("/tmptmp", simout.client.Root)
eq({"//depot/a/... //C/x/...", '"//depot/b /..." //C/y/...'}, simout.client.View)
e.stdin = nil

-- ** "client -i" rejects client with invalid View

e.stdin = [[
Root:	/tmptmp

Client:	C

View:
	//depot/a/... //C/x/...
	//depot/b /... //C/y/...
]]
simp4 "-s client -i"
lookfor "error: Error in client specification"


simp4 "fstat -Rc //depot/..."
lookfor "%.%.%. depotFile //depot/"

simp4 "-s fstat -Rc //depot/...file"
lookfor [[info1: depotFile //depot/a/file
info1: clientFile /tmp/s4/a/file
info1: isMapped.
info1: haveRev 1
info1: action edit
.*info1: depotFile //depot/a/newfile
.*info1: action add
]]

simp4 "-s fstat -Rc ./..."
lookfor [[info1: depotFile //dx/y
info1: clientFile /tmp/s4/y
]]

-- extra space after "isMapped" is consistent with actual p4
simp4 "-s fstat -Ol ./..."
lookfor [[info1: depotFile //dx/y
info1: clientFile /tmp/s4/y
info1: isMapped.
info1: fileSize 2
]]

---- where
-- There are two types of failures, and oddly one returns an exit code
-- of '0' and one returns an exit code of '1'.
--
-- error: . - file(s) not in client view.
-- exit: 0
--
-- error: .. - must refer to client 'bhk-mac'.
-- exit: 1

simp4 "-s where qq"
lookfor [[info: //dx/qq //C/s4/qq /tmp/s4/qq
exit: 0
]]

simdat.depotCWD = nil
simp4 "-s where ../../qq"
lookfor [[^error: .-
exit: 1
]]

-- notice the weird depot-relative behavior of "local" relative paths...
simp4 "-s where ../dx/qq"
lookfor [[info: //dx/qq //C/s4/qq /tmp/s4/qq
exit: 0
]]

---- sync

local cwd = xpfs.getcwd()
qt.printf("cwd = %s\n", cwd)

simdat.client.Root = cwd
simdat.depotCWD = "//dx"

simp4 "sync y"

lookfor( "//dx/y %- refreshing " .. pquote(cwd) .. "/s4/y" )
eq( "=y", F.read("s4/y") )
eq( 1, simout.haves["//dx/y"] )

simdat = simout
simp4 "-s sync y"
lookfor [[^error: .*y %- file%(s%) up%-to%-date%.
exit: 0
$]]

---- sync -f

simdat = simout
xpfs.remove("s4/y")
simp4 "-s sync -f y"
lookfor( "^info: //dx/y %- refreshing " .. pquote(cwd) .. "/s4/y\nexit: 0" )
eq( "=y", F.read("s4/y") )
-- cleanup
assert(F.rm_rf("s4"))


---- sync -p

simdat = simout
simdat.haves = nil
simp4 "-s sync -p y"
lookfor( "^info: //dx/y %- refreshing " .. pquote(cwd) .. "/s4/y\nexit: 0" )
eq( "=y", F.read("s4/y") )
assert( not simout.haves["//dx/y"] )
-- cleanup
assert(F.rm_rf("s4"))

---- sync -n

simdat = simout
simdat.haves = nil
simp4 "-s sync -n y"
lookfor( "^info: //dx/y %- refreshing " .. pquote(cwd) .. "/s4/y\nexit: 0" )
eq( nil, (F.read("s4/y")) )
assert( not simout.haves["//dx/y"] )

---- revert

simp4 "-s revert //depot/..."
lookfor [[
^info: //depot/a/file#1 %- was edit, reverted
info: //depot/a/newfile#none %- was add, abandoned
exit: 0
$]]
eq( {}, simout.actions )

---- fstat

simdat = simout
simp4 "-s fstat -Rc //depot/...newfile"
lookfor "^error: [^\n]*\nexit: 0\n$"


-- errors written to stderr (when "-s" NOT specified)

simdat = simout
simp4 "fstat -Rc //depot/...newfile"
if e.stderr then
   qt.match(e.stderr, "no such file")
end


---- changes

simp4 "-s changes -m 1 //..."
lookfor "^info: Change 999 on 2010/01/01 by bhk"

---- alternate server (-p)

simdat.ports = {
   ["s2:1666"] = {
      files = {
         ["//src/a"] = "=a",
         ["//src/b"] = "=b",
      },
      actions = {
         ["//src/a"] = "edit",
      },
      haves = {
         ["//src/a/"] = 1,
      },
      depotCWD = "//src",
      client = {
         Root = "/tmp/s2",
         Client = "CS2",
         View = {
            "//src/... //CS2/..."
         },
      },
      info = { "Server address: s2.com:1666" },
   }
}

simp4 "-p s2:1666 -s fstat //..."
lookfor [[info1: depotFile //src/a
info1: clientFile /tmp/s2/a
info1: isMapped.
info1: action edit
info1: depotFile //src/b
info1: clientFile /tmp/s2/b
]]
qt.match(simout.log[1], "%-p s2:1666 %-s fstat //%.%.%.")

simdat = simout
simp4 "-p s2:1666 -s info"
lookfor [[info: Server address: s2.com:1666]]
lookfor [[exit: 0]]

---- alternate clients (-c)

simdat.clients = {
   cb = {
      actions = {
         ["//depot/a/file"] = "edit",
      },
      haves = {
         ["//depot/a/file"] = 5,
         ["//depot/b/x"] = 6,
      },
      client = {
         Root = "/tmp/CB",
         Client = "CB",
         View = {
            "//depot/... //CB/...",
         }
      },
   }
}
simp4 "-c cb fstat //..."
lookfor [[
%.%.%. depotFile //depot/a/file
%.%.%. clientFile /tmp/CB/a/file
%.%.%. isMapped.
%.%.%. haveRev 5
%.%.%. action edit

%.%.%. depotFile //depot/b/x
%.%.%. clientFile /tmp/CB/b/x
%.%.%. isMapped.
%.%.%. haveRev 6

%.%.%. depotFile //depot/c/x
%.%.%. clientFile /tmp/CB/c/x
%.%.%. isMapped.

%.%.%. depotFile //dx/y
]]


---- handling "special" characters

local simdatSpecial = simdat
simdat.files = {
   ["//depot/a"] = "A",
   ["//depot/b/!$$&'(),:;<=>?[]^_`{|}~"] = "B",
   ["//depot/c/%40"] = "@"
}
simdat.client.View = {
   "//depot/... //C/...",
}
simdat.client.Root = cwd
simp4 "-s print //depot/b/!$$&'(),:;<=>?[]^_`{|}~"
lookfor "text: B"


simdat = simdatSpecial
simp4 "-s print //depot/c/%40"
lookfor "text: @"


simdat = simdatSpecial
simp4 "sync //depot/c/..."
eq( "@", (F.read("c/@")) )


simdat = simdatSpecial
simp4 "where //depot/c/%40"
eq("//depot/c/%40 //C/c/%40 " .. simout.client.Root .. "/c/@",
          (e.out:match("[^\n]+")))

---- ultimate escape hatch: hook

simdat.hook = [[
   local a, b, c = ...
   if a == "foo" then
     table.insert(simdat.log, "HOOKED")
     scriptMode(true)
     put("error", "%s %s", b, c)
     print("PRINT")
     exit(3)
   end
]]
simp4 "foo a b"
lookfor "^error: a b\nPRINT\nexit: 3\n$"
eq("foo a b", simout.log[1])
eq("HOOKED", simout.log[2])

--------------------------------

os.remove(".simdat")

print "simp4 ok"
