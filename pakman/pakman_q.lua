-- pakman_q : test pakman.lua or pakman executable file
--
-- By default, this loads and calls 'pakman.lua' directly, but it will test
-- a compiled executable form of pakman if given a "pakman=<exe>" argument.
-- These tests rely on 'simp4'.  The command to use to invoke simp4 can be
-- specified via the SIMP4 env var, or "simp4=<exe>" on the command line.
--
-- For debugging, use env vars:
--   pakman_q="a b c"      =>  run only tests a, b, and c
--   pakman_q="-V"         =>  run all tests in verbose mode
--   pakman_q="-V a b c"   =>  verbose mode + only a,b,c
--   pakman_q="-PASS"      =>  skip & pretend success so downstream
--                              targets can be built/tested
--
-- Look at <tmp>/pakmanlog to see p4x's interaction with simp4
--
-- Command-line arguments:
--    pakman=<exe> : executable to test (optional)
--    simp4=<exe>  : simp4 command [alternative: $SIMP4 ]
--    tmp=<tmpdir> : temp dir to use; defaults to $OUTDIR
--    v=1          : verbose [alternative: ${pakman_q}=V ]
--
-- Environment vars:
--    pakman_q       = tests to run and/or options
--    SIMP4          = simp4 command
--    OUTDIR         = directory for temporary files
--

local qt = require "qtest"
local xpfs = require "xpfs"
local fu = require "lfsu"
local TE = require "testexe"
local sysinfo = require "sysinfo"

local eq, match = qt.eq, qt.match

local bWin = (xpfs.getcwd():sub(2,2) == ":")

----------------------------------------------------------------
-- process command line options
----------------------------------------------------------------

local vars = {}
for _,a in ipairs(arg) do
   local name, val = a:match("(.-)=(.*)")
   if not name then error("args take form: name=value") end
   vars[name] = val
end

local opts = os.getenv("pakman_q") or ""
vars.v = vars.v or opts:upper():match("[^%s]+") == "-V"

local function verbose(...)
   if vars.v then qt.printf(...) end
end

local function absify(name, default, isexe)
   local val = vars[name] or default
   if val then
      val = fu.abspath( val )
      if isexe and bWin then
         val = val:gsub("/", "\\")
      end
      vars[name] = val
      verbose("%s = %s\n", name, val)
   end
end

-- Find lua exe that is running this script
absify("pakman", nil, true)
absify("simp4", os.getenv("SIMP4"), true)
absify("tmp", os.getenv("OUTDIR"))
assert(vars.tmp, "OUTDIR not set")

do
   local n, luacmd = -1, nil
   while arg[n] do
      luacmd = arg[n]
      n = n - 1
   end
   absify("lua", luacmd, true)
end

local workdir = vars.tmp .. "/PT"
verbose("** pakman_q workdir = %s\n", workdir)

----------------------------------------------------------------
-- Construct environment for invoking pakman
----------------------------------------------------------------

local defaultConfig = [[
  -- .pakman file
  vcs.p4 = {
    command = <SIMP4>
  }
  log = "+../pakmanlog"
]]

local e = TE:new(vars.pakman or "@pakman.lua", vars.v)
e.bTee = vars.v
local defaultSimdat

local function clone(t)
   if type(t) ~= "table" then return t end
   local t2 = {}
   for k,v in pairs(t) do
      t2[clone(k)]= clone(v)
   end
   return t2
end

-- merge a and b : returns 'b' unless both a and b are tables:
--   where keys collide and values are both tables, recursively merger
--   where keys collide and values are not both tables, use b
local function merge(a,b)
   if type(a) ~= "table" or type(b) ~= "table" then
      return b
   end
   local t = {}
   for k,v in pairs(a) do
      t[k] = clone(v)
   end
   for k,v in pairs(b) do
      t[k] = merge(t[k], v)
   end
   return t
end


-- Reset FS state: create files listed in files[] and delete all others
-- under current directory (except for files starting with ".").
--
local function initFS(files, top)
   for _,f in ipairs(xpfs.dir(top or ".")) do
      if f:sub(1,1) ~= "." then
         fu.rm_rf(f)
      end
   end

   for k,v in pairs(files or {}) do
      local parent = fu.splitpath(k)
      assert(fu.mkdir_p(parent))
      -- write file unless we are just creating the directory
      if not k:match("/%.$") then
         local ro, data = v:match("(%%?)(.*)")
         assert(fu.write(k, data))
         if ro == "%" then
            xpfs.chmod(k, "-w")
         end
      end
   end
end


local function getsimdat()
   return assert(loadfile(".simdat"))()
end


local function lookfor(pat)
   -- don't use a tail call; it makes error "level" handling complicated
   local t = table.pack(e:expect(pat, 2))
   return table.unpack(t, 1, t.n)
end


-- If 'host' is non-nil, it limits results to those in which the p4 command
-- specifies "-p <host>"
--
local function expectSyncs( syncs, prefix )
   local pat = "sync (.*)"
   if prefix then
      pat = prefix:gsub("[-.+%%]", "%%%1") .. ".* "..pat
   end
   return eq( TE.sort(syncs), TE.sort(TE.grep(getsimdat().log or {}, pat)))
end


-- pakman:  run pakman with 'args' after initializing .simdat and FS contents
--    args   = arguments to pass to pakman.
--    simdat = contents of .simdat file (simp4 configuration)
--    files  = tree describing initial file system contents underneath cwd;
--             see initFS()
--
-- args may begin with a prefix:
--   "!" => ignore errors and warnings
--   "*" => ignore warnings
--
-- Otherwise, this function will assert that no errors or warnings were
-- generated.
--
local function pakman(args, simdat, files)
   local warns, args = args:match("([!%*]?)(.*)")

   initFS(files)
   assert(fu.write(".simdat", qt.format("return %Q", assert(simdat or defaultSimdat))))

   e:exec( (vars.v and "-v " or "") .. args)

   e.out = e.out:gsub("\r\n","\n")

   if warns ~= "!" then
      -- assert no errors
      if type(e.retval) == "number" and e.retval ~= 0 then
         error("Pakman returned error: "..e.retval, 2)
      end
      local w = e.out:match("Unrecognized option: [^\n]*") or
                e.out:match("[^\n]-Error[^\n]*") or
                e.out:match("exited with error")
      if w then
         qt.printf("Error messages emitted:\n%s\n", w)
         error("No errors expected", 2)
      end
   end

   if warns == "" then
      -- assert no warnings
      local w = e.out:match("%*%*%* [^\n]*")
      if w then
         qt.printf("Warnings emitted:\n%s\n", w)
         error("No warnings expected", 2)
      end
   end
end


local make = TE:new("make")

----------------------------------------------------------------
--  Test Environment
----------------------------------------------------------------

-- defaultSimdat holds the simp4 configuration file (.simdat) used by most
-- tests.  .simdat describes the state of the P4 server(s).
--
defaultSimdat = {
   -- server state: info, files

   info = { "Server address: S.bogo.com:1666" },
   files = {},

   -- client state: client, depotCWD, haves, actions

   client = {
      Root = workdir,
      Client = "test",
      View = { "//depot/... //test/..."}
   },

   -- SIMP4 needs us to specify 'depotCWD' -- the depot location
   -- corresponding to the current working dir -- in order for it to be able
   -- to handle relative paths and local->depot translations.  We assume cwd
   -- == workdir, which maps back to "//depot".
   depotCWD = "//depot",
}

-- Merge provided simdat structure with defaultSimdat
--
local function newSim(s)
   return merge(defaultSimdat, s)
end


-- Merge provided files with defaultSimdat
--
local function newSimFiles(newFiles)
   return newSim{ files = newFiles }
end


-- Create a new simdat client.  This is a subset of the top-level simdat
-- structure.
--
--   fs = FS table in which to create root "directory" for this client, or nil.
--
local function newSimClient(name, fs)
   if fs then
      fs[name.."/."] = true
   end
   return {
      client = {
         Client = name,
         Root = workdir.."/"..name
      }
      -- optional: haves, actions, depotCWD
   }
end


-- Create a new simdat (server state) structure for simp4.
--    root = workdir .. /<name>
--    fs   = as in newSimClient
--
local function newSimServer(name, fs, defaultClientName)
   local s = newSimClient(defaultClientName or name, fs)
   s.info = { "Server address: " .. name .. ".bogo.com:1666" }
   s.clients = {}
   s.files = {}
   return s
end


----------------------------------------------------------------
-- Tests
--
-- Tests generally follow this pattern:
--
-- 1. Construct a simdat (simp4 configuration) that describes the desired
--    server-side preconditions for the test.  Use newSim() and
--    newSimFiles() to construct variations of the default configuration.
--
-- 2. Construct a table that describes the FS preconditions for the test.
--    The table lists all files that should exist and their contents.  Most
--    tests specify no table and use the default, which is an empty table
--    (no local files).
--
-- 3. Call pakman().  This executes pakman with the specified arguments
--    after initializing the server-side and FS state (e.g. creating and
--    deleting files).
--
-- 4. Assert post-conditions:
--      * command output:  use 'lookfor' or e.out
--      * resulting server state:  use getsimdat()
--      * resulting FS state:  use fu.read()
--
-- Default environment for tests:
--   client root directory:      OUTDIR
--   current working directory:  OUTDIR
--   which maps to P4 location:  //depot
--
-- Some tests validate functional requirements.  These should document them
-- in comments, enumerating each requirement validated in a test function.
--
-- Other tests may validate internal assumptions.
--
----------------------------------------------------------------


local ut = qt.tests


--------------------------------
-- basic tests
--------------------------------
function ut.version()
   -- 1. The version command shall display a version number.

   pakman "version"
   lookfor "pakman [%d%?]%.[%d%?]"
end


function ut.badCommand()
   -- 1. For invalid sub-commands, pakman shall display an indicative error
   -- message.
   pakman ("!xunkx")

   lookfor "pakman: Unknown subcommand 'xunkx'%.  Try"
end

--------------------------------
-- 'get' command
--------------------------------

function ut.getInvalid()
   -- 1. Display an indicative error message when an non-existent VCS
   --    location is given to 'pakman get'.
   pakman("!get p4://S/d/f")
   lookfor "pakman: Invalid location: .-/d/f"
   lookfor "exited with error"
end


function ut.getHostError()
   -- 1. When host name does not match 'p4 info', provide a descriptive
   --    error mesage.

   pakman("!get p4://FOO/depot/x")

   -- verify that proper variables are used
   lookfor('p4 is configured for host S')
   lookfor('URI = p4://FOO/depot/x')
   lookfor('p4 command = .*simp4.*')
end


function ut.getDepotConflict()
   --  1. When a portion of a tree is mapped, fail & report "partially-mapped".

   local s = newSim {
      files = { ["//depot/partial/file"] = "some file" },
      client = {
         View = {
            "//depot/... //test/depot/...",
            "-//depot/partial/x/... //test/depot/partial/x/..."
         }
      }
   }
   pakman("!get p4://S/depot/partial", s)
   lookfor "partially"
   expectSyncs{}

   -- 2. "--force" causes pakman to proceed anyway.

   pakman("*get p4://S/depot/partial/...@1 --force", s)
   expectSyncs{"//depot/partial/...@1"}
end


function ut.getClientConflict()
   --  1. When the default (mapLong)local mapping of a package root is already
   --     taken, a client-side conflict should be reported.

   local s = newSim {
      files = { ["//depot/new/file"] = "some file" },
      client = {
         View = { "//depot/nothing/... //test/pakman/..." }
      }
   }
   pakman("!get p4://S/depot/new/...", s)
   lookfor "client path conflict"
   expectSyncs{}
end


function ut.getMapped()
   -- 1. When plain directory ("/...") is specified, 'pak' file is ignored
   -- 2. Directory will be synced.
   -- 3. Specified version is synced.

   local s = newSimFiles {
      ["//depot/a/pak"] = "error()",
   }
   pakman("get p4://S/depot/a/...@33", s)
   lookfor "syncing p4://S.bogo.com/depot/a/%.%.%.@33"
   expectSyncs{ "//depot/a/...@33" }
end


function ut.getUnmapped()
   -- 1. When un-mapped directory is specified, it will be added to client.
   -- 2. When no version is given by user, the latest changelist on the server
   --    should be used.

   local s = newSim {
      files = {
         ["//depot/a/file"] = "A"
      },
      client = {
         View = { "//depot/nothing/... //test/nothing/..." }
      }
   }

   pakman("get p4://S/depot/a/...", s)
   local v = getsimdat().client.View
   eq( "//depot/a/... //test/pakman/depot/a/...", v[#v])
   expectSyncs{ "//depot/a/...@999" }
end


function ut.getPakURI()
   -- 1. Package may be specified by URI for pak file.
   -- 2. Default package root is the directory containing the pak file.
   -- 3. Dependency URIs may specify versions.
   -- 4. Dependency URIs without specified versions inherit version from
   --    their package.
   -- 5. Pakfiles can refer to dependencies via relative URIs.

   local s = newSimFiles {
      ["//depot/b/file"] = "B",
      ["//depot/c/file"] = "C",
      ["//depot/d/altpak"] = [[
         deps = { C="p4://S/depot/c@20", B="../b/..." }
      ]],
   }
   pakman( "get p4://S/depot/d/altpak@19", s )
   expectSyncs { "//depot/c/...@20", "//depot/b/...@19", "//depot/d/...@19" }

   -- 6. "p4:///path" defaults to default server

   pakman( "get p4:///depot/d/altpak@22", s )
   expectSyncs { "//depot/c/...@20", "//depot/b/...@22", "//depot/d/...@22" }

   -- 7. "//path" on command line is equivalent to "p4:///path"

   pakman( "get //depot/d/altpak@23", s )
   expectSyncs { "//depot/c/...@20", "//depot/b/...@23", "//depot/d/...@23" }

   -- 8. "\\server\path" on command line is treated as UNC path.

end


function ut.getFile()
   -- 1. Local files: a local file or directory that lies within the
   --    current client view should be treated as equivalent to the
   --    corresponding "p4:" URI.
   --
   -- 1(a) 'pakman get' accepts local directory viaa relative path.

   local s = newSimFiles {
      ["//depot/r/pak"] = [[ deps = { C="../c@1" }  ]],
      ["//depot/c/file"] = "C"
   }
   pakman("get r@33", s)
   lookfor "syncing p4://S.bogo.com/depot/c/%.%.%.@1"
   expectSyncs{ "//depot/c/...@1", "//depot/r/...@33" }

   -- 1(b) 'pakman get' accepts local pakfile via relative path.

   s = newSimFiles {
      ["//depot/pak"] = "print('URI='..uri); files = {}"
   }
   pakman("get pak", s)
   lookfor "URI=p4://S.bogo.com/depot/"

   -- 1(c) "p4 where" returns a strange result when the local path
   --      is mapped with a view line that shadows a previous view line.

   -- Use a bogus local path to make sure that the simp4 hook handles the
   -- 'where' response
   s.hook = [[
         local cmd = table.concat({...}, " ")
         local r = simdat.client.Root:gsub("\\", "/")
         if cmd:match("%-s where x/pak/%.%.%.") then
            scriptMode(true)
            put("info", "-//depot/xyz/... //test/x/pak/... ".. r .. "/x/pak/...")
            put("info", "-//depot/qrs/... //test/x/pak/... ".. r .. "/x/pak/...")
            put("info", "//depot/pak/... //test/x/pak/... " .. r .. "/x/pak/...")
            exit(0)
         end
   ]]
   pakman("get x/pak", s)

   -- 2. When 'get' is passed a FS path that is *not* within the current
   --    client view, a "file:" URI will be used.

   -- 2(a) file not mapped but under client root ['p4 where' exit code == 0]

   local s = newSim {
      client = {
         View = { "//depot/mapped/... //test/mapped/..." }
      }
   }
   local files = {
      pak = "print('URI='..uri)"
   }
   pakman("get pak", s, files)
   lookfor "URI=file:.-PT/"

   -- 2(b) file not under client root ['p4 where' exit code == 1]

   local s = newSimServer("p4", files)
   pakman("get pak", s, files)
   lookfor "URI=file:.-PT/"

   -- 3. When a local, writable copy of a file exists, it will be used
   --    instead of the corresponding VCS file.
   -- 4. When a local, read-only copy of a file exists:
   --    (a) the corresponding VCS file will be used, if it exists.
   --    (b) the local file will be used if the VCS file does not exist.
   -- 5. When a local directory exists and the corresponding VCS directory
   --    does not exist, it will be recognized as a valid directory.
   -- 6. When using a local files for "p4:" URIs, print a "Using local..."
   --    warning.

   local s = newSimFiles {
      ["//depot/rw/pak"] = "error()",
      ["//depot/ro/pak"] = "print('SERVER='..uri)",
   }
   local files = {
      ["rw/pak"]  = "deps = { A='../ro/pak', B='../fnx/pak', C='../dnx/...' }",
      ["ro/pak"]  = "%error()",
      ["fnx/pak"] = "%print('FILE='..uri)",
      ["dnx/x"]   = "DNX/X"
   }

   pakman("*get p4://S/depot/rw/pak", s, files)

   lookfor "Using locally edited[^\n]-/rw/pak"
   lookfor "Using local[^\n]-/fnx/pak"
   lookfor "SERVER=p4://[^\n]-/ro/pak"
   lookfor "FILE=p4://[^\n]-/fnx/pak"
   expectSyncs{ "//depot/ro/...@999",
                "//depot/rw/...@999",
                "//depot/fnx/...@999",
                "//depot/dnx/...@999" }
end


function ut.getAlias()
   -- Test cases involving different URIs that address the same package
   -- due to Pakman's auto-detection of package type.
   --
   -- 1. "p" => "p/pak" when p/pak is a file
   -- 2. "p" => "p/..." when p is a directory and p/pak is not a file
   -- 3. "p/" => "p/pak" when p/pak is a file
   -- 4. "p/" => "p/..." when p is a directory and p/pak is not a file

   local s = newSimFiles {
      ["//depot/a/pak"]  = 'deps = { P1 = "../p1", D1 = "../d1" }', -- 1 & 2
      ["//depot/p1/pak"] = 'deps = { P2 = "../p2/" }',              -- 3
      ["//depot/p2/pak"] = 'deps = { D2 = "../d2/"}',               -- 4
      ["//depot/d1/file"] = 'D1',
      ["//depot/d2/file"] = 'D2',
   }

   pakman("get a/pak@1", s)
   -- If all dirs were synced, then all pak files were recognized, and all
   -- directories were also recognized.
   expectSyncs{ "//depot/a/...@1",
                "//depot/p1/...@1",
                "//depot/p2/...@1",
                "//depot/d1/...@1",
                "//depot/d2/...@1" }

   -- 5. "p/" will not match the *file* "p".

   pakman("!get a/pak/@1", s)
   expectSyncs {}
   lookfor "Not a file or directory"
   lookfor "   File: /depot/a/pak"
end


function ut.getVersionConflict()
   -- 1. When two versions of the same package root are requested, Pakman
   --    exits with a version conflict error.

   local s = newSimFiles {
      ["//depot/a/pak"] = 'deps = { B="../b", C="../c/...@1" }',
      ["//depot/b/pak"] = 'deps = { C="../c/...@2" }',
      ["//depot/c/foo"] = 'C/FOO'
   }
   pakman( "!get p4://S/depot/a/pak", s)
   lookfor "conflict"
end


function ut.brokenPrintS()
   -- 1. If the P4 client returns lines of text in response to "-s print"
   --    lacking a status prefix, default to "text:".  This was observed on
   --    one broken P4 client version on one user's machine.

   local brokenSimdat = newSim {
      brokenPrintS = "true",
      files = {
         ["//depot/b/file"] = "b/file",
         ["//depot/d/pak"] = [[ deps = { B="p4://S/depot/b@3"} ]],
      },
   }
   pakman( "get p4://S/depot/d@1", brokenSimdat )
   lookfor "syncing p4://S.*/depot/b/%.%.%."
   expectSyncs{ "//depot/d/...@1", "//depot/b/...@3" }
end


function ut.describe()
   -- 1. The 'describe' command shall retrieve a package tree description
   --    (visit) and display a user-readable representation of the tree.

   local s = newSimFiles {
      ["//depot/a/pak"] = "deps={B='../b?Debug'}",
      ["//depot/b/file"] = "B"
   }
   pakman("describe p4://S/depot/a/pak", s)
   lookfor "%+%-> | +b %(Debug%) +|"
end


function ut.deprecated()
   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            get { B = '../b/...' }
            min "a.min"
            mak "a.mak"
            cmd "make"
      ]],
      ["//depot/b/file"] = "file"
   }
   pakman("*get p4://S/depot/a/pak@1", s)
   expectSyncs { "//depot/a/...@1", "//depot/b/...@1" }
   match((fu.read("a/a.min")), "B ?=")
   match((fu.read("a/a.mak")), "tree ?:")
   lookfor "deprecated[^\n]-min"
   lookfor "deprecated[^\n]-mak"
   lookfor "deprecated[^\n]-get"
   lookfor "deprecated[^\n]-cmd"
end


-- **deprecated** custom mapPackage function
local function _old_customMap()
   local s = newSimFiles {
      ["//deep/n/o/p/q/r/s/dir/fx"] = "fxdata",
   }
   local fs = {}
   fs.cfg =  [[
         require ".pakman"
         function p4.mapPackage(p, isOkay)
            local name = ""
            repeat
               local head, tail = p:match("(.*)(/[^/]*)$")
               if not head then
                  return
               end
               name = tail .. name:gsub("/", "%.")
               p = head
            until isOkay(name)
            return name
         end
   ]]

   -- "top" is already mapped from the depot, so expect "s.top"
   pakman( "--config=cfg get p4://S/deep/n/o/p/q/r/s/dir/...", s, fs)
   eq("fxdata", (fu.read("../s.dir/fx")))
end


function ut.warnP4Client()
   -- 1. Print a warning message when Cygwin clients are detected.
   -- 2. Print a warning when the 'Client root' reported by p4 info
   --    is not valid.

   local s = newSimServer("S")
   s.os = "CYGWIN"
   s.files = { ["//d/x"] = "" }

   pakman( "*get p4://S/d/x@33", s)
   lookfor "%*%*%* CYGWIN version"
   lookfor "root directory does not exist"
end


----------------------------------------
-- tests for PAK file properties/env
----------------------------------------

function ut.pakParams()
   -- ** Parameters values specifed in the query part ("?a=b;...") are made
   --    available to the package file via the 'params' table.
   --
   -- ** URIs identifying the same PAK file but with different parameters
   --    should be treated as distinct packages (the package file should be
   --    processed twice).
   --
   -- ** Two instances of the same pakfile should see the same <pak>.shared.
   --
   -- ** Changes made to <pak>.params by the pakfile will be applied to
   --    <pak>.uri.
   --
   -- ** <pak>.params is callable as a function to validate a schema.
   --
   -- ** <pak>.params assigns "default" values.
   --
   -- ** <pak>.deps accepts locations as strings or tables


   local s = newSimFiles {
      ["//depot/a/xpak"] = [[
         params {
            x = {},
            y = {default="2"}
         }
         deps = {
            A = "pak",
            B = {path="pak", params = params}
         }
         glue[1] = { path="x.min", template="B_URI=#{pkg.children.B.uri}" }
      ]],
      ["//depot/a/pak"] = [[
            print("a:pak:x=[".. (params.x or "") .. "]")
            params.z = "3"
            shared.xs = shared.xs or {}
            table.insert(shared.xs, params.x or "X")
            table.sort(shared.xs)
            print("x="..table.concat(shared.xs, ":"))
      ]]
   }
   pakman("get p4://S/depot/a/xpak?x=1", s)
   expectSyncs{ "//depot/a/...@999" }
   e:expect("a:pak:x=%[%]")
   e:expect("a:pak:x=%[1%]")
   match((fu.read("a/x.min")), "B_URI=p4://S.bogo.com/depot/a/pak%?x=1;y=2;z=3")
   lookfor "x=1:X"
end


function ut.pakCommand()
   -- 1. <pak>.commands.make specifies what MAK files contain
   -- 2. <pak>.commands.make/clean/maketree can use variable substitution
   -- 3. Pakman should print out commands required to build
   --   a) Command to build tree.
   --   b) Command to build just package.
   -- 4. <pak>.commands.* can be functions; these are passed the substitution env.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            deps = { B= "../b/...", C="../x/c/pak" }
            glue = { "x.mak" }
            commands.make = "#{paths.B}/make"
            commands.clean = "#{pkg.root}clean"
            commands.maketree = "#{pkg.root}tree"
      ]],
      ["//depot/b/x"] = "b/x",
      ["//depot/x/c/pak"] = [[
            deps = { B = "../../b/..." }
            commands.make = function (env)
                               return env.paths.B .. "/waf"
                            end
      ]]
   }

   pakman("get a/pak", s)
   expectSyncs{ "//depot/a/...@999", "//depot/b/...@999", "//depot/x/c/...@999" }
   lookfor("To build:\n.- cd a\n")
   lookfor("/depot/a/tree +# builds the package and")
   lookfor(" ../b/make +# builds just")

   local mak = fu.read("a/x.mak")
   match(mak, "/depot/a/clean")

   match(mak, "tree *:[^\n]*\n[^\n]*,,%.%./b/make,")
   match(mak, "C *:[^\n]*\n[^\n]*,%.%./x/c,%.%./%.%./b/waf,")
end


function ut.pakGlue()
   -- 1. <pak>.glue array can hold:
   --    a) File names ending in ".min" -> MIN files
   --    b) File names ending on ".mak" or named '[Mm]akefile' -> MAK files
   --    c) Table
   -- 2. MIN file variables
   --    a) Dep var for each child package
   --    b) Dep var values are relative paths (relative to CWD)
   -- 3. MAK files properly build each child package.
   --    a) verbose=true => all output from sub-builds
   --    b) default => one line per sub-build ("making ...")
   --    b) default => all output when VERBOSE=1 is specified in make
   -- 4. The first MAK file will be used to generate the default commands
   --    for building the package: "make -f <mak>"

   local s = newSimFiles {
      ["//depot/c/pak"] = [[ commands.make = "make" ]],
      ["//depot/c/makefile"] = "all: ; @echo making_c\n\n",

      -- test relative file handling
      -- and old & new syntax
      ["//depot/mt/pak"] = [[
            deps = { CDIR = "p4://S/depot/c/pak" }
            table.insert(glue, "x.min")
            table.insert(glue, { type="min", path="m.x" })
            table.insert(glue, { path="neat.mak" })
            table.insert(glue, { path="verbose.mak", verbose=true})
            table.insert(glue, "mindir/min")
            table.insert(glue, "makdir/mak")
            commands.make = "make -f top.mak"
      ]],

      ["//depot/mt/top.mak"] = [[
            include mindir/min
            top_dflt: ; @echo making_mt $(CDIR)/file
      ]],
   }

   pakman( "get p4://S/depot/mt/pak@9", s)
   lookfor "make %-f neat.mak *# builds the package and its dependencies"
   expectSyncs{ "//depot/c/...@9", "//depot/mt/...@9" }

   match((fu.read("mt/x.min")) ,  "CDIR *:?= *%.%.")
   match((fu.read("mt/m.x")) ,  "CDIR *:?= *%.%.")
   match((fu.read("mt/neat.mak")) ,  "_clean *%:")

   make:exec "-C mt -f verbose.mak"
   make:expect "making_c\n.*making_mt mindir/%.%./%.%./c/file"

   make:exec "-C mt -f neat.mak"
   -- Note: In Win32 make, an extra space appears at the end of the line due to
   -- the way "&&" is handled in "echo making . && ..."

   -- Note: The value for "_@" pass may leak through from the enclosing
   -- environment (the make that runs these tests), so allow for extra output.
   make:expect "making ../c ?\n.-making . ?\n"

   make:exec "-C mt -f neat.mak VERBOSE=1"
   make:expect "making_c\n.*making_mt mindir/%.%./%.%./c/file"

   -- 4. Target names should be child names when there is no conflict with
   --    other target names.  Each target so named should build the
   --    corresponding package and its subtree.

   -- 5. When child names collide with other child names or reserved targets
   --    ("tree", "tree_clean", "all", "clean"), non-conflicting target
   --    names should be chosen.

   -- 6. When "=" or other problematic characters appear in the package name,
   --    an alternate make target name will be chosen.

   -- 7. MAK files should not issue redundant build commands when building
   --    the tree.  Check the following cases:
   --     a) a package appears as a dependency of multiple packages
   --     b) multiple variants exist with the same root & command

   local s = newSimFiles {
      -- a & c include redundant variants of b
      -- b includes a problematic variable name for d
      ["//depot/a/pak"] = [[ commands.make="echo make_a" ; deps={ b="../b/pak", c="../c/pak" };
            glue = { {path="x.mak", verbose=true} }
      ]],
      ["//depot/b/pak"] = [[ commands.make="echo make_b" ; deps = { ['='] = "../d/pak" } ]],
      ["//depot/c/pak"] = [[ commands.make="echo make_c" ; deps={ b="../b/pak?1" } ]],
      ["//depot/d/pak"] = [[ commands.make="echo make_d" ]]
   }
   pakman("get p4://S/depot/a/pak@1", s)
   expectSyncs{ "//depot/a/...@1", "//depot/b/...@1",
                "//depot/c/...@1", "//depot/d/...@1" }
   make:exec "-C a -f x.mak"
   make:expect "make_d.-make_b.-make_c.-make_a"

   -- does not make b twice:  (allow for extrnaous output when _@ is defined)
   eq(nil, (make.out:match("\nmake_b.*\nmake_b")))

   -- 8. "Redundant build commands" does not include packages that have different
   --    sets of dependencies (which might otherwise introduce a circular dependency).

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            glue = { {path="x.mak", verbose=true} }
            deps.luatool = "../tools/pak?lua"
      ]],
      ["//depot/tools/pak"] = [[
            commands.make = "echo make_tools="..(params[1] or "")
            if params[1] == "lua" then
               deps.lt = "../luatool/pak"
            end
      ]],
      ["//depot/luatool/pak"] = [[
            commands.make = "echo make_luatool"
            deps.tc = "../tools/pak?c"
      ]],
   }
   pakman("get p4://S/depot/a/pak@1", s)
   make:exec "-C a -f x.mak"
   make:expect "make_tools=c.-make_luatool.-make_tools=lua"

   -- 9. Warn when glue contains non-array elements

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ glue = { path="x.min" } ]]
   }
   pakman("*get p4://S/depot/a/pak@1", s)
   lookfor("%*%*%* Warning.-glue")
end


function ut.warnConflict()
   -- 1. Warn when two pacakges write different contents into the same file.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            deps = { AA="../x/pak?a", AB="../x/pak?b", AC="../x/pak?a;c" }
      ]],
      ["//depot/x/pak"] = [[
            local tmpl = params[1].."\n"
                         .. (params[2] or "x") .. "// IGNORE_GLUE_CONFLICT\n"
            glue[1] = { path = "x.min", template = tmpl }
      ]],
   }
   pakman("*get p4://S/depot/a/pak@1", s)
   lookfor "%*%*%*.-glue file conflict.-x.min.-x/pak@1%?a\n"
   lookfor "%*%*%*.-glue file conflict.-x.min.-x/pak@1%?b\n"
   -- AA conflicts with AB, AC conflicts with AB, AA does not conflict with AA
   eq(2, select(2, e.out:gsub("%*%*%*.-glue file conflict", "")))
end


function ut.warnNested()
   -- 1. Warn when one package root is underneath another's.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ deps = { B = "b/..."} ]],
      ["//depot/a/b/foo"] = "foo",
   }
   pakman("*get p4://S/depot/a/pak@1", s)
   lookfor("%*%*%*.-nested")
end


function ut.pakGlueTemplate()
   -- 1. glue.template can be used to override the MIN file template.
   -- 2. glue.template = "+..." can be used to appen to the default MIN file
   --    template.
   -- 3. Default template defines the following: __pkg_deps, __pkg_root,
   --    __pkg_version, __pkg_result, __pkg_uri
   -- 4. "#{var.field}" replaced with var.field.
   -- 5. In variable expansions, "\" and "#" are properly quoted.

   local tmpl = [[
D=#{defs}
C=#{pkg.children.A.root}
G=#{glueFile.type}
V=#{vars}
P=#{paths.A}
X=#{glueFile.x}
]]
   local tmplOut = [[
D=A = %.%./a
C=p4://S.-/depot/a/
G=min
V=A
P=%.%./a
X=a\#\\\#b
]]
   local s = newSimFiles {
      ["//depot/a/file"] = "A",
      ["//depot/tmpl/pak"] = [[
         deps = { A="p4://S/depot/a/..." }
         glue = {
            { path="a.min", template = [=[]] ..tmpl .. [[]=], x='a#\\#b' },
            { path="b.min", template = "+FOO=1\n" },
         }
      ]]
   }
   pakman("get p4://S/depot/tmpl/pak", s)
   match((fu.read("tmpl/a.min"):gsub("\r", "")), tmplOut:gsub("\r", ""))

   local min
   local function e(exp)
      match(min, "\n *"..exp.."\n", 2)
   end

   min = fu.read("tmpl/b.min")
   e("FOO=1")
   e("__pkg_version %?= 999")
   e("__pkg_deps *:=.-")
   e("__pkg_result *:=.-")
   e("__pkg_root *:= .-")
   e("__pkg_uri *%?= p4://S.bogo.com/depot/tmpl/pak")
end


function ut.pakGlueFunction()

   -- 1. `glue` field can be a function that is called after child packages
   --     are processed.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            deps.B = "../b/pak"
            function glue(env)
               return {
                  { path = "x.min", template = env.paths.B }
               }
            end
      ]],
      ["//depot/b/pak"] = [[result = 'XrX']]
   }

   pakman("get p4://S/depot/a/pak@1", s)
   eq("../b/XrX", fu.read("a/x.min"))
end



function ut.pakRedir()
   -- 1. <pak>.redir property specifies a redirection

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ deps = { B = "../b/pak" } ; glue = { "x.min" } ]],
      ["//depot/b/pak"] = [[ redir = '../b/pak2' ]],
      ["//depot/b/pak2"] = [[ redir = { path = "../c/pak" } ]],
      ["//depot/c/pak"] = [[ result = 'out' ; glue = { "y.min"}  ]]
   }
   pakman("get a/pak", s)
   expectSyncs{ "//depot/a/...@999", "//depot/c/...@999" }
   match(( fu.read("c/y.min") ), "min file")
   match(( fu.read("a/x.min") ), "B = %.%./c/out")
end


function ut.pakResult()
   -- 1. <pak>.result specifies what parent packages see
   -- 2. <pak>.result can use variable substitution

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            deps = { B = "../b", C = "../c" }
            glue = { "x.min" }
      ]],
      ["//depot/b/pak"] = [[ result = "out" ]],
      ["//depot/c/pak"] = [[
            deps = { B = "../b" }
            result = "#{paths.B}/outc"
      ]]
   }
   pakman( "get a/pak@1", s)
   expectSyncs{ "//depot/a/...@1", "//depot/b/...@1", "//depot/c/...@1" }

   local min = fu.read("a/x.min")
   match(min, "B = %.%./b/out\r?\n")
   match(min, "C = %.%./b/out/outc\r?\n")
end


function ut.pakFiles()
   -- 'root' and 'files'
   --
   -- 1. <pak>.root specifies the top of the source tree (the dir to be
   --    synced and mapped).
   -- 2. <pak>.files specifies an array of P4 patterns that identify sets of
   --    files that need to be synced.
   -- 3. File patterns are relative to the root directory.
   -- 4. When one 'files' pattern is a subset of another one, it should be
   --    consolidated for efficiency into a single sync.

   local s = newSimFiles {
      ["//depot/pak"] = [[
            root = "a"
            files = {"b", "c/...", "c...", "c/x/..."}
      ]]
   }
   pakman( "get p4://S/depot/pak@1", s)
   expectSyncs{ "//depot/a/b@1", "//depot/a/c...@1" }

   -- 6. When patterns overlap but not completely, they will be synced
   --    separately.

   local s = newSimFiles {
      ["//depot/pak"] = 'files = { "a/...x", "a/...y" }'
   }
   pakman( "get p4://S/depot/pak@1", s)
   expectSyncs { "//depot/a/...x@1", "//depot/a/...y@1" }

   -- 7. <pak>.files cannot specify files outside of the root directory.
   --    a) via ".."
   --    b) via absolute paths

   local s = newSimFiles {
      ["//depot/a/pak"] = 'files = { "../b/..." }'
   }
   pakman( "!get p4://S/depot/a/pak@1", s)
   lookfor( "Error" )
   expectSyncs {}

   local s = newSimFiles {
      ["//depot/a/pak"] = 'files = { "/depot/b/..." }'
   }
   pakman( "!get p4://S/depot/a/pak@1", s)
   lookfor( "Error" )
   expectSyncs {}

   -- 8. Conflicts between versions are detected when <pak>.files is used
   --    (not only when "..." is synced)

   local s = newSimFiles {
      ["//depot/a/pak"] = 'files = { "file"} ; deps = {A="./...@2" }'
   }
   pakman( "!get p4://S/depot/a/pak@3", s)
   lookfor( "conflict" )
   expectSyncs {}

end


function ut.pakWarning()
   -- 1. Warn when package file assigns global variables.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ bar = 1 ]]
   }
   pakman( "*get p4://S/depot/a/pak", s)
   lookfor("%*%*%* Warning.-unknown global variable")
end


function ut.pakEnvironment()
   -- 1. 'sys' table is available to packages.
   -- 2. 'pmlib' is available to packages. [pmlib_q covers the internal
   --    functional correctness of the pmlib functions.]

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            print("sys=" .. sys.os)
            print("pmlib=" .. (pmlib.mapShort and "ok" or ""))
      ]]
   }
   pakman( "get p4://S/depot/a/pak@1", s )
   lookfor "sys=%a"
   lookfor "pmlib=ok"
end


function ut.pakMapping()
   -- 1. Basic tests
   --   a) package can set 'mapping'
   --   b) packages inherit 'mapping'
   --   c) first preference is used when available
   --   d) second preference is used when first is not available
   --   e) new name is manufactured when no preferences are available

   local s = newSim {
      files = {
         ["//map/a/b/c/pak"] = [[
            mapping = function (p) return {"/a", p.rootPath:match("/[^/]+$")} end
            deps = { X = "../x/pak" }
         ]],
         ["//map/a/b/x/pak"] = [[
            deps = { X2 = "../../c/x/..." }
         ]],
         ["//map/a/c/x/f"] = "/A/C/X",
      },
      client = {
         View = { "//depot/... //test/depot/..." }
      }
   }
   pakman( "get p4://S/map/a/b/c/pak", s)
   expectSyncs{ "//map/a/b/c/...@999",
                "//map/a/b/x/...@999",
                "//map/a/c/x/...@999" }

   eq( { "//depot/... //test/depot/...",
         "//map/a/b/c/... //test/a/...",
         "//map/a/b/x/... //test/x/...",
         "//map/a/c/x/... //test/x-2/..." },
       getsimdat().client.View )

   -- 2. User defaults
   --    a) "--mapshort" specifies pmlib.mapShort
   --    b) "mapping = pmlib.mapShort" specifies pmlib.mapShort

   local s = newSim {
      files = { ["//map/a/b/c/x"] = "X" },
      client = {
         View = { "//depot/... //test/depot/..." }
      }
   }

   -- "--mapshort" option
   pakman( "get --mapshort p4://S/map/a/b/c/...", s)
   expectSyncs{ "//map/a/b/c/...@999" }
   eq( { "//depot/... //test/depot/...",
         "//map/a/b/c/... //test/pkg/c/..."},
       getsimdat().client.View )

   -- config file defaults
   pakman( "get --config=cfgfile p4://S/map/a/b/c/...",
           merge(s, {files = { ["//map/a/b/c/x"] = "X" } }),
           { cfgfile = [[ require ".pakman" ; mapping = pmlib.mapShort]] })
   expectSyncs{ "//map/a/b/c/...@999" }
   eq( { "//depot/... //test/depot/...",
         "//map/a/b/c/... //test/pkg/c/..."},
       getsimdat().client.View )

   -- 3. End-to-end pmlib.mapShort/mapLong tests
   --   a) mapShort works (initial preference & some fallbacks)
   --   b) mapLong works
   --   c) "-2" fallback is used when mapLong result is unavailable

   local s = newSim {
      files = {
         ["//map/a/b/c/x/pak"] = [[
               mapping = pmlib.mapShort
               deps = { ABDX = "../../d/x/pak" }
         ]],
         ["//map/a/b/d/x/pak"] = [[ deps = { ACDX = "/map/a/c/d/x/pak" } ]],
         ["//map/a/c/d/x/pak"] = [[ deps = { Y = "../y/pak" } ]],
         ["//map/a/c/d/y/pak"] = [[ mapping = pmlib.mapLong ]],
      },
      client = {
         View = {
            "//depot/... //test/depot/...",
            "//map/other/... //test/pakman/map/a/c/d/y/..."
         }
      }
   }
   pakman( "get p4://S/map/a/b/c/x/pak", s)
   eq( { "//depot/... //test/depot/...",
         "//map/other/... //test/pakman/map/a/c/d/y/...",
         "//map/a/b/c/x/... //test/pkg/x/...",
         "//map/a/c/d/x/... //test/pkg/d-x/...",
         "//map/a/b/d/x/... //test/pkg/b-d-x/...",
         "//map/a/c/d/y/... //test/pakman/map/a/c/d/y-2/..." },
       getsimdat().client.View )
end


function ut.pakSelf()
   -- 1. `self` refers to the package object itself.
   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            rawset(self, "root", "../b")
      ]],
      ["//depot/b/f"] = "f"
   }
   pakman("get p4://S/depot/a/pak@1", s)
   expectSyncs{ "//depot/b/...@1" }
end


function ut.pakMessage()
   local s = newSimFiles {
      ["//depot/a/pak"] = [[ message = "Nothing to build." ]],
      ["//depot/b/pak"] = [[ message = function (p) return "got "..p.uri end ]]
   }

   pakman("get p4://S/depot/a/pak@1", s)
   lookfor "Nothing to build"

   pakman("get p4://S/depot/b/pak@1", s)
   lookfor "got p4:"
end


function ut.pakRetval()
   -- 1. If a package returns a table, that will be taked as the package
   --    description instead of the environment (globals set by the
   --    pakfile).

   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            return { root = "../b" }
      ]],
      ["//depot/b/f"] = "f"
   }
   pakman("get p4://S/depot/a/pak@1", s)
   expectSyncs{ "//depot/b/...@1" }
end


function ut.pakErrors()
   -- 1. Print a standard Lua error when a syntax error is encountered.
   -- 2. Print informative error messages when:
   --    a) deps is assigned to something other than a table
   --    b) deps contains a non-string value
   --    c) deps contains a non-string key
   --    d) variable substitution references unknown field

   local function expectError(str, msgpat)
      pakman("!get p4://S/depot/pak@1", newSimFiles { ["//depot/pak"]=str })
      if e.out:match("stack traceback%:") then
         error("pakman did not handle error", 2)
      end
      local a,b = lookfor "\npakman: Error in package file: ([^\n]*)\n([^\n]*)\n"
      match(a, "pak@1")
      match(b, msgpat)
   end

   expectError('!',                   '^pak:1: unexpected')
   expectError('deps = "a"',  "deps is a string value %(should be a table%)")
   expectError('deps = {a = true}',   'deps contains an invalid entry')
   expectError('deps = {[true]="a"}', 'deps contains an invalid entry%:')
   expectError('return"foo"',         'returned.-string')
   expectError('result = "#{notvalid}"',  'unknown variable reference')
end


function ut.loadfile()
   -- 1. package files can include other files via require
   -- 2. required files can access globals
   -- 3. readfile() can be used to retrieve file contents, using path
   --    relative to source file.

   local s = newSimFiles {
      ["//depot/test.pak"] = [[
            root = require "mod.lua"
            print("x="..readfile"pkg/x")
      ]],
      ["//depot/mod.lua"] = 'return pairs and "/depot/pkg" or "/depot/nopairs"',
      ["//depot/pkg/x"] = 'X',
   }

   pakman( "get p4://S/depot/test.pak@7", s)
   lookfor("x=X")
   expectSyncs{ "//depot/pkg/...@7" }
end


function ut.multiServer()
   -- 1. one package can refer to a different server
   -- 2. both packages are synced to the appropriate place
   -- 3. coalescing of 'files' patterns is done per-server
   local fs = {}

   -- Configuration: default server -> S;  "T" -> T
   local sdT = newSimServer("T", fs)
   sdT.client.View = { "//depot/... //T/..." }
   sdT.files = {
      ["//depot/a/pak"] = '--TA'
   }

   local sdS = newSimServer("S", fs)
   sdS.client.View = { "//depot/... //S/..." }
   sdS.ports = { ["T:1666"] = sdT }
   sdS.files = {
      ["//depot/a/pak"] = [[
            --SA
            deps = { TA = "//T/depot/a/...@100" }
            files = { "pak" }
            glue = {"x.min"}
      ]]
   }

   fs.cfgfile = [[
         require ".pakman"
         local cmd = vcs.p4.command
         vcs.p4.command = {
            T = cmd .. " -p T:1666 -u userT -P pwdT",
            [""] = cmd
         }
   ]]

   pakman( "get --config=cfgfile p4://S/depot/a/pak", sdS, fs )

   -- examine all syncs (ignoring host/port info)
   expectSyncs{ "//depot/a/pak@999",
                "//depot/a/...@100" }

   -- examine syncs only for T
   expectSyncs( { "//depot/a/...@100" }, "-p T")

   match((fu.read("S/a/pak")), "%-%-SA")
   match((fu.read("S/a/x.min")), "TA = %.%./%.%./T/a")
   eq("--TA", (fu.read("T/a/pak")))
   eq(nil, (fu.read("T/pakman/depot/a/x.min")))

   -- 4. Automatically attempt to connect using "-p" when host name is specified
   --    in package location.
   --     (a) Host name without port
   --     (a) Host name with port

   local fs = {}
   local sdS = newSimServer("S", fs)

   local sdT = newSimServer("T", fs)
   sdT.client.View = { "//depot/... //T/..." }
   sdT.files = {
      ["//depot/a/pak"] = "--TA"
   }

   local sdU = newSimServer("U", fs)
   sdU.client.View = { "//depot/... //U/..." }
   sdU.files = {
      ["//depot/a/pak"] = "--U:8080"
   }

   sdS.ports = {
      ["T:1666"] = sdT,
      ["U:8080"] = sdU
   }
   pakman("get p4://T/depot/a/pak", sdS, fs)
   eq("--TA", (fu.read("T/a/pak")))

   pakman("get p4://U:8080/depot/a/pak", sdS, fs)
   eq("--U:8080", (fu.read("U/a/pak")))

end


function ut.multiClient()
   -- 1. vcs.p4.command can be used to direct requests for different
   --    sub-trees of of a repository to different P4 command strings.
   -- 2. Maps are correctly applied to the proper workspace.
   -- 3. Maps are correctly applied when two p4.command entries refer to the
   --    same client.

   local fs = {}
   local s = newSimServer("S", fs, "CA")
   s.clients.cb = newSimClient("CB", fs)
   s.files = {
      ["//src/pak"] = 'deps.A = "../deploy/pak" ',
      ["//deploy/pak"] = 'deps.T = "../tools/...@100" ',
      ["//tools/file"] = 'TOOLS/FILE',
   }

   fs.cfgfile = [[
         require ".pakman"
         vcs.p4.command = {
            ["/tools"] = vcs.p4.command .. " -c cb",
            ["/src"] = vcs.p4.command,
            [""] = vcs.p4.command
         }
   ]]

   pakman( "get --config=cfgfile p4://S/src/pak", s, fs)

   lookfor "mapping //deploy"
   lookfor "mapping //src"
   lookfor "mapping //tools"

   eq( { "//tools/... //CB/pakman/tools/..." },
       getsimdat().clients.cb.client.View )

   eq( { "//src/... //CA/pakman/src/...",
         "//deploy/... //CA/pakman/deploy/..." },
       getsimdat().client.View)

   -- examine all syncs (ignoring host/port info)
   expectSyncs{ "//deploy/...@999",
                "//tools/...@100",
                "//src/...@999" }

   -- examine syncs only for client 'cb'
   expectSyncs( { "//tools/...@100" }, "-c cb")

   match((fu.read("CA/pakman/src/pak")), "deps.A ")
   match((fu.read("CA/pakman/deploy/pak")), "deps.T ")
   eq("TOOLS/FILE", (fu.read("CB/pakman/tools/file")))

end


----------------------------------------
-- Other tests
----------------------------------------

function ut.hookPackageGlue()
   -- 1. packageGlue hook can be set and is called.
   -- 2. pkg.fsRoot, pkg.children, plg.glue are valid.

   local simdatHook = newSimFiles {
      ["//depot/pga/file"] = "pga/file contents",
      ["//depot/pgb/file"] = "pgb/file contents",
      ["//depot/pg/pak"] = [[
            deps = { a = "../pga",  b = "../pgb" }
            glue = { "pak.min", "pak.mak" }
            commands.make = "make"
      ]],
   }
   local fs = {}
   fs.cfg = [[
         require ".pakman"
         local function myhook(pkg)
            local t = {}
            for name,child in pairs(pkg.children) do
               table.insert(t, name .. "=" .. child.fsRoot:match("[^/]*$"))
            end
            table.sort(t)
            for _,g in ipairs(pkg.glue) do
               if g.type == "min" then
                  g.data = "# <" .. table.concat(t,";") .. ">\n" .. g.data
               end
            end
         end
         addHook("packageGlue", myhook)
   ]]

   pakman("--config=cfg get p4://S/depot/pg/pak@1", simdatHook, fs)
   expectSyncs{ "//depot/pga/...@1", "//depot/pgb/...@1", "//depot/pg/...@1" }
   local min = fu.read("pg/pak.min")
   match(min, "^# <a=pga;b=pgb>\n")
end


function ut.hookOnVisit()
   local fs = {}
   fs.cfg = [[
         require ".pakman"
         local function onVisit(pm)
            for n,p in ipairs(pm.pkgs) do
               print(n.." "..p.uri)
            end
         end
         addHook("onVisit", onVisit)
   ]]
   local s = newSimFiles {
      ["//a/pak"] = "deps = { B='../b/pak' }",
      ["//b/pak"] = "deps = { C='../c/...' }",
      ["//c/f"] = "C/F"
   }
   pakman( "visit p4://S/a --config=cfg", s, fs)
   lookfor "1 p4://.-/a/pak"
   lookfor "2 p4://.-/b/pak"
   lookfor "3 p4://.-/c/%.%.%."
end


function ut.optLog()
   -- 1. "--log=<file>" option logs activity to a file:
   --    (a) pakman arguments are reported
   --    (b) tranactions with p4 are reported
   --    (c) exit code is reported

   local s = newSimFiles {
      ["//depot/b/file"] = "B",
   }
   pakman("!get p4://S/depot/a --log=xx", s)
   local xx = fu.read("xx")
   match(xx, "^%* pakman %d.-%* Command: .-pakman.-|get.-\n# exit: 1\n$")
   match(xx, "\n%% [^\n]*simp4 %-V >\n| Perforce")

   -- 2. "--log=+<file>" appends to a file.

   pakman("get p4://S/depot/b --log=+xx", s, { xx = "PREVIOUS" })
   xx = fu.read("xx")
   match(xx, "^PREVIOUS%* pakman 0.9.-%* Command: .-\n# exit: 0\n$")
end


function ut.optP4sync()
   -- 1. "--p4-sync=<opt>" specifies an option to be passed to 'p4 sync'
   -- 2. Multiple "--p4-sync" options accumulate.

   local s = newSimFiles {
      ["//depot/a/file"] = "some file",
   }
   pakman("get p4://S/depot/a@33 --p4-sync=n --p4-sync=p --p4-sync=n", s)
   lookfor "syncing p4://S.bogo.com/depot/a/%.%.%.@33"
   expectSyncs{ "-n -p //depot/a/...@33" }
end


local function ut_script()
   -- "--script" option: obsolete & deprecated
   local s = newSimFiles {
      ["//depot/script/pak"] = [[
            glue = { "x.mak" }
            commands.make = "make"
            result = "out"
      ]]
   }
   pakman( "get p4://S/depot/script/pak --script", s)
   lookfor "%.%.%. fsRoot .*script\n"
   lookfor "%.%.%. fsResult .*script/out\n"
   lookfor "%.%.%. treeMake make %-f x%.mak\n"
end


function ut.depotConflictSelf()
   -- 1. Pakman should sidestep depot conflicts within a single package
   --    tree, by first mapping packages that have shorter paths.
   local s = newSim {
      files = {
         ["//depot/a/pak"] = [[ deps = { A="../x/y/...", B = "../x/...", C = "../x/y/z/..." } ]],
         ["//depot/x/y/z/file"] = "file"
      },
      client = {
         View = { "//depot/a/... //test/depot/a/..."}
      }
   }
   pakman( "!get p4://S/depot/a/pak@1", s)
   expectSyncs{ "//depot/a/...@1", "//depot/x/...@1" }
end


function ut.bailOnLoop()
   -- 1. Detect and error out when package dependencies infinitely recurse.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ deps = { A="../a?x" .. (params[1] or "") } ]]
   }
   pakman("!get p4://S/depot/a/pak", s)
   lookfor "recursion"
end


function ut.warnCycle()
   -- 1. Detect and warn when there is a circular dependency (during the
   --    'visit' stage).

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ deps = { B="../b" } ]],
      ["//depot/b/pak"] = [[ deps = { A="../a" } ]],
   }
   pakman("*visit p4://S/depot/a/pak", s)
   lookfor "%*%*%*.-circular"
   lookfor "B in .-/a/pak"
   lookfor "A in .-/b/pak"
end


--------------------------------
-- previously-encountered issues
--------------------------------

function ut.errFileRoot()
   -- Bug fixed: When package root is "file:///tmp" while package URI is
   -- "p4://sever/y", map was created for "p4://server/tmp/..."

   local s = newSimFiles {
      ["//depot/p.pak"] = "root = 'file:///tmp'"
   }
   pakman("get p.pak", s)
   eq(nil, getsimdat().client.View[2])
end


function ut.errAutoDetect()
   -- Bug fixed in 0.96: Auto-detection was short-cutted by previous package
   -- cache.  When looking for "/A", "/A/..." would prevent "/A/pak" from
   -- being detected.

   local s = newSimFiles {
      ["//depot/a/pak"] = [[ deps = { C = "../c/...", B = "../b/pak" } ]],
      ["//depot/b/pak"] = [[ deps = { C = "../c" } ]],   -- should get ../c/pak
      ["//depot/c/pak"] = [[ print("c/pak".." included") ]]
   }

   pakman("get p4://S/depot/a/pak", s)
   expectSyncs{ "//depot/a/...@999", "//depot/b/...@999", "//depot/c/...@999" }
   lookfor("c/pak included")
end


function ut.errMakCD()
   -- Bug fixed in 0.96: When a "file:" package referred to a "p4:" package,
   -- its generated mak files would 'cd' to the wrong directory (with an
   -- initial "/" in front of what should be a relative path)

   local s = newSim {
      files = {
         ["//depot/a/pak"]      = [[ commands.make = "make" ]],
         ["//depot/a/Makefile"] = [[ all: ; echo MADE ]],
      },
      -- Unmap CWD to get a "file:" URI for fpak
      depotCWD = false,
      client = {
         View = { "//depot/a/... //test/depot/a/..."}
      },
   }
   local f = {
      fpak = [[ deps = { A = "p4://S/depot/a/pak" }
                glue = { {path="f.mak", verbose=true}}
             ]]
   }
   pakman("get fpak", s, f)
   expectSyncs{ "//depot/a/...@999" }
   make:exec( "-f f.mak" )
   make:expect("MADE")
end


function ut.errDeleted()
   -- Bug fixed in 0.981: Deleted pak files were treated like valid,
   -- zero-length files.

   local s = newSimFiles{}
   s.hook = [[
      -- Respond to "print //depot/a/pak" as p4 would for a deleted file
      local args = table.concat({...}, " ")
      if args:match("print .-//depot/a/pak@") then
         simdat.hooked = true
         scriptMode(args:match("%-s "))
         exit(0)
      end
   ]]
   pakman("!get p4://S/depot/a/pak", s)
   lookfor "Invalid location"
   eq(true, getsimdat().hooked)
   expectSyncs{}
end


function ut.fragment()
   -- 1. URI fragment denotes subset of (or place within) the package results.
   local s = newSimFiles {
      ["//depot/a/pak"] = [[
            deps = { B = "../b/...#file" }
            glue = { "x.min" }
      ]],
      ["//depot/b/file"] = "file",
      ["//depot/b/x/y"] = "y",
   }
   pakman("get p4://S/depot/a/pak@1", s)
   expectSyncs { "//depot/a/...@1", "//depot/b/file...@1" }
   match((fu.read("a/x.min")), "\nB *= *../b/file\r?\n")
end


local pmuri = require "pmuri"
local function p4Encode(s)
   return (s:gsub("[#@%%%*]", pmuri.byteToHex))
end


function ut.specials()
   -- Punctuation characters syntactically significant or disallowed in ...
   --
   --   ALL  ! " # $ % & ' ( ) * + , - . / : ; < = > ? @ [ \ ] ^ _ ` { | } ~
   --    sh  ! " # $   & ' ( ) *             ; <   > ?   [ \ ]     ` { | } ~
   --  make      # $ %                     :     =         \
   --   CMD    "     % &   ( )     ,           <   >   @   \   ^       |
   --  NTFS    "               *           :   <   > ?     \           |
   --    p4      #   %         *                       @
   --
   -- p4 says: "Can't add filenames with wildcards [@#%*] in them. Use -f
   -- option to force add."  So while they are to be avoided, they are
   -- supported.  '"' seems to be completely unsupported by p4.

   -- ** Files in depot with special characters can be read, mapped, and
   --    synced into the local file system under the proper name.
   -- ** Find local files, not existing on p4, with special characters.
   -- ** "p4 where" will find depot files with special characters.

   -- all ASCII punctuation except '"' and '/', plus spaces
   local ugly = "! # $ % & ' ( ) * + , - . : ; < = > ? @ [ \\ ] ^ _ ` { | } ~"
   if sysinfo.os == "WinNT" then
      ugly = ugly:gsub("[%*:<>%?\\|]", "")   -- omit NTFS illegal characters
   end

   local uglypak = "/depot/" .. ugly .. "/pak"
   local uri = pmuri.gen{ scheme="p4", host="S", path = uglypak}

   local s = newSim{
      files = {
         ["/"..p4Encode(uglypak)] = [[ print("PAK_OK") ]],
         ["//depot/%40/pak"] = "deps = { A = [[" .. uri .. "]] }",
      },
      depotCWD = "//depot",
      client = {
         Root = workdir,
         View = { "//depot/%40/... //test/%40/..." }
      },
   }

   -- ignore "*** Using locally edited" warning
   pakman("*get %40/xx", s, { ["@/xx"] = "redir = 'pak'" })

   lookfor "PAK_OK"
   match((fu.read("pakman" .. uglypak)), "PAK_OK")
   match((fu.read("@/pak")), "deps =")

   -- test that <ugly> was mapped
   eq(string.format('"//depot/%s/..." "//test/pakman/depot/%s/..."',
                    p4Encode(ugly), p4Encode(ugly)),
      getsimdat().client.View[2])
end


function ut.make()
   -- For this test we need to actually invoke an executable.  Since it
   -- should be available on all supported platforms, we will use the lua
   -- executable that is running this script (stored in vars.lua)

   -- 1. `pakman make <uri>` will get the URI and then execute the make
   --    command, in the correct directory.

   local function newpak(s)
      return s:gsub("lua", vars)   -- replace "lua" with vars.lua
   end

   local s = newSimFiles {
      ["//depot/a/pak"] = newpak[==[
            commands.maketree = [[lua -e "io.open('x','w'):write('Hello')"]]
      ]==]
   }
   pakman("make a/pak", s)
   lookfor "Making"
   eq("Hello", fu.read("a/x"))

   -- 2. If there is no command, pakman should report so.

   local s = newSim {
      files = {
         ["//depot/a/file"] = "A",
      },
   }

   pakman("!make p4://S/depot/a/...", s)
   lookfor "No command to make"

   -- 3. If a make command returns an exit code, return that exit code.

   local cmd = string.format([[commands.maketree = "%s -e \"os.exit(3)\""]],
                             vars.lua:gsub("\\", "\\\\"))
   local s = newSim {
      files = {
         ["//depot/a/pak"] = cmd
      },
   }
   pakman("!make p4://S/depot/a/pak", s)

   -- e.retval is null when running an actual executable (the pakman_TEST
   -- case), but it holds the correct value when we invoke a script.

   if e.retval and e.retval > 256 then
      -- Lua 5.2.2 os.execute() on Linux *still* returns shifted value
      e.retval = e.retval / 256
   end
   eq(3, e.retval or 3)
end

--------------------------------
-- run tests
--------------------------------

local startdir = xpfs.getcwd()
fu.rm_rf(workdir)
xpfs.mkdir(workdir)
xpfs.chdir(workdir)

fu.write(".pakman", defaultConfig:gsub("<SIMP4>", "[["..vars.simp4.."]]"))

local rv = qt.runTests()

if rv == 0 then
   -- clean up only on success
   xpfs.chdir(startdir)
   fu.rm_rf(workdir)
end

return rv
