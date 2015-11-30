----------------
-- pm_q
----------------

-- For debugging, set an environment variable:
--   pm_q=-V

local qt = require "qtest"
local xpfs = require "xpfs"
local map = require "cmap"
local Object = require "object"
local fu = require "lfsu"

local pmLocals = {
   "P4", "Sys", "Package", "File", "checkParams", "varExpand", "createTargets",
   "findNestedRoots", "findCycle", "p4ParseClient", "p4ParseInfo", "p4MapDir",
   "p4GenClient", "p4ClientToLocal", "p4MatchesHost", "p4MatchesPath"
}
local PM, _PM = qt.load("pm.lua", pmLocals)  -- @require pm

local workdir = assert(os.getenv("OUTDIR")):match("(.-)/?$")

local bVerbose = (os.getenv("pm_q") or ""):match("%-[vV]")

local T = qt.tests
local eq = qt.eq
local LOG = qt.logvar

local function pathnorm(path)
   path = path:gsub("\\", "/"):gsub("^[A-Z]", string.lower)
   return path
end

local clone = require("list").clone

local function pquote(str)
   return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"):gsub("%z", "%%z"))
end

-- local function expectError(f, ...)
--    local o = { pcall(f, ...) }
--    if o[1] then
--       qt.printf("f(%Q) -> %Q\n", {...}, o)
--    end
--    eq(false, o[1], 2)
-- end

----------------------------------------------------------------
-- tests of utility functions
----------------------------------------------------------------

function T.checkParams()
   local schema, params

   local function e(result)
      local o = { pcall(_PM.checkParams, params, schema) }
      if type(result) == "string" then
         -- error: result = pattern to match
         qt._eq(false, o[1], 2)
         qt.match(o[2], result)
      else
         -- success
         if not o[1] then
            print(o[2])
         end
         qt._eq(true, o[1], 2)
         qt._eq(result, params, 2)
         qt._eq({true, table.unpack(params)}, o)
      end
   end

   local x, y, z = "x", "y", "z"

   -- ** When a parameter NOT in the schema is IN params => error.

   schema = {}
   params = { b = "x" }
   e "param"

   schema = { a = {default="x"} }
   params = { b = "x" }
   e "param"

   -- ** When a parameter IN the schema is IN params:
   --    1. typ.values is non-nil:
   --      a) values is empty => okay
   --      b) value is in values => okay
   --      c) values has members, value is not in it => error

   schema = { a = { values = {} } }
   params = { a = "x" }
   e { a = "x" }

   schema = { a = { values = { "x", "y"} } }
   params = { a = "x" }
   e { a = "x" }

   params = { a = "z" }
   e "value"

   --    2. typ.values is nil, typ holds values:
   --      a) values is empty => okay
   --      b) value is in values => okay
   --      c) values has members, value is not in it => error

   schema = { a = { } }
   params = { a = "x" }
   e { a = "x" }

   schema = { a = { "x", "y"} }
   params = { a = "x" }
   e { a = "x" }

   params = { a = "z" }
   e "value"

   -- ** When a parameter IN the schema is NOT in params:
   --      a) 'optional' => no error, not in result
   --      b) 'default' => no error, default value in result
   --      c) otherwise => error

   schema = { a = { "x", "y", optional=true },
              { "p", "q", optional=true },
           }
   params = {}
   e {}

   schema = { a = { "x", "y", default = "x" },
              { "p", "q", default = "p" } }
   params = {}
   e { "p", a = "x" }

   schema = { a = { "x", "y"} }
   params = {}
   e "param"

   schema = { a = {} }
   params = {}
   e "param"

   -- ** Parameters named in the "alias" attribute of a paramter type are
   --    converted to the parameter name associated with that type.

   schema = { {alias="a", optional=true} }
   params = { a = "A" }
   e { "A"}

   -- ** Alias parameters do not clobber the actual (non-alias) parameters.

   schema = { {alias="a"}, v = { alias="Variation"}, {alias="b", optional=true} }
   params = { v = "x", a="A" }
   e { v="x", "A"}

   -- ** Positional parameters with value "" will be have default, if any,
   --    applied.

   schema = { {default="x"}, a={default="y"} }
   params = {"", a=""}
   e { "x", a="" }

   -- ** Return unpack(params)

   eq({"a","b"},  {_PM.checkParams({"a",x="1"}, {{},{default="b"}, x= {}})} )
end


function T.varExpand()
   local tbl = {
      a = 1,
      t = {
         b = 2,
         _c_ = 3,
         u = { d4 = 4 },
      }
   }

   eq("a#b", _PM.varExpand("a#b"))
   eq("abc", _PM.varExpand("a#{x}c", {x="b"}))
   eq("\\#", _PM.varExpand("#{#}"))
   eq("#\\##", _PM.varExpand("##{#}#"))

   eq([[a\#b]], _PM.varExpand("#{a}", {a=[[a#b]]}) )
   eq([[a\\\#b]], _PM.varExpand("#{a}", {a=[[a\#b]]}) )

   eq("a1b2c3d4e", _PM.varExpand("a#{a}b#{t.b}c#{t._c_}d#{t.u.d4}e", tbl))
end


function T.createTargets()
   local function newPkg(cmd, deps)
      return {
         children = deps or {},
         expanded = {
            commands = { make = cmd }
         },
      }
   end

   -- check quoting of characters problematic in make targets
   local t = _PM.createTargets( newPkg(nil, { ["a$:=# |\\z"] = newPkg("foo") }) )
   eq("a^24^3A^3D^23^20^7C^5Cz", t[1].name)

   -- non-tree graph
   local p3 = newPkg("m3")
   local p2 = newPkg("m2", {a = p3} )
   local p1 = newPkg(nil, {a = p2, b=p3})
   local t = _PM.createTargets(p1)
   eq(3, #t)
   -- print(   qt.describe(t, nil, nil, " ") )

   -- eliminate redundant make commands
   local p4 = newPkg("dup")
   local p3 = newPkg("dup")
   local p2 = newPkg("m2", {a = p3, b=p4} )
   local p1 = newPkg(nil, {a = p2, b=p3})
   local t = _PM.createTargets(p1)
   eq(3, #t)
   eq("dup", t[1].make)
end


function T.findNestedRoots(pkg)
   local pkgs = {
      { root = "p4://S/a/b/c/d/" },
      { root = "p4://R/a/" },
      { root = "p4://R/a/" },
      { root = "p4://S/a/b/c/de" },
      { root = "p4://S/a/b/" },
      { root = "p4://S/a/b/c/" },
   }
   local nests = _PM.findNestedRoots(pkgs)
   eq(3, #nests)
   eq("p4://S/a/b/",     nests[1].top.root)
   eq("p4://S/a/b/c/",   nests[1].btm.root)
   eq("p4://S/a/b/",     nests[2].top.root)
   eq("p4://S/a/b/c/d/", nests[2].btm.root)
   eq("p4://S/a/b/",     nests[3].top.root)
   eq("p4://S/a/b/c/de", nests[3].btm.root)
end


function T.findCycle(pkg)

   -- construct package graph with cycles
   local function fc(graph)
      for name,pkg in pairs(graph) do
         pkg.uri = name
         pkg.children = map.ix(function (v) return v, graph[v] end)(pkg)
      end
      local c = _PM.findCycle(graph.a)
      local uris = (map.i "v.node.uri .. v.childName")(c)
      return table.concat(uris,':')
   end

   eq("bb", fc { a={"b", "c"}, b={"b"}, c={} })

   eq("ab:bc:ca", fc { a={"b"}, b={"c"}, c={"a"} })

   eq("ac:cd:da", fc {
         a = { "b", "c"},
         b = { },
         c = { "d" },
         d = { "a" }
   })
end


----------------------------------------------------------------
-- TestSys
----------------------------------------------------------------

local TestSys = Object:new()

-- results is table that describes ProcWrite return values (pattern -> text)
--
function TestSys:initialize(results, bPrint)
   self.fs = {}
   self.log = ""
   self.results = results or {}
   self.bPrint = not not bPrint
   self.messages = {}
end

function TestSys:logF(...)
   local str = string.format(...)
   self.log = self.log .. str
   if self.bPrint then
      print("sh: " .. str:gsub("\n", "|"))
   end
end

function TestSys:printF(...)
   self.messages[#self.messages+1] = string.format(...)
end

function TestSys:output(cmd)
   for pat,val in pairs(self.results) do
      if cmd:match(pat) then
         return val
      end
   end
end

function TestSys:procRead(cmd)
   self:logF("%% %s\n", cmd)
   if self.bPrint then
      for line in self:output(cmd):gmatch("[^\n]+") do
         print(" | " .. line)
      end
   end
   return self:output(cmd)
end

function TestSys:procWrite(cmd, input)
   self:logF("%% %s<<%s##\n", cmd, input)
end

function TestSys:writeFile(fname, content)
   self.fs[fname] = content
end

----------------------------------------------------------------
-- p4 tests
----------------------------------------------------------------


local p4ClientSample = string.gsub([[
#This:	is a comment

a:	 spaces\32

b:
\09
	line2

xx:

]], "\\(..)", string.char)


function T.p4ParseClient()
   local function ParseClient(str)
      local t = {}
      for a in str:gmatch("([^\r\n]*)\r?\n") do
         table.insert(t, a)
      end
      return _PM.p4ParseClient(t)
   end
   local a = ParseClient(p4ClientSample)

   eq({"a","b","xx",a=" spaces ",b={"","line2"},xx={}}, a)

   local a,b = ParseClient("a:name\n")
   eq(nil, a)
   eq("E2 (unrecognized syntax)", b)

   local a,b = ParseClient("a:\nname\n")
   eq(nil, a)
   eq('E1 (in "a:")', b)
end


function T.p4MatchesHost()
   local base = "aa.b.c"

   eq(true, _PM.p4MatchesHost(base, ""))
   eq(true, _PM.p4MatchesHost(base, ":1666"))

   eq(true, _PM.p4MatchesHost(base, "aa"))
   eq(true, _PM.p4MatchesHost(base, "aa.b"))
   eq(true, _PM.p4MatchesHost(base, "aa.b.c"))
   eq(true, _PM.p4MatchesHost(base, "aa.b.c:1666"))
   eq(true, _PM.p4MatchesHost(base, "aa:1666"))
   eq(false, _PM.p4MatchesHost(base, "aa:100"))
   eq(false,  _PM.p4MatchesHost(base, "a"))

   -- terminating "." => fully qualified address
   eq(false, _PM.p4MatchesHost(base, "aa."))
   eq(false, _PM.p4MatchesHost(base, "aa.b."))
   eq(true, _PM.p4MatchesHost(base, "aa.b.c."))
end


function T.p4MatchesPath()
   assert( _PM.p4MatchesPath("/a/b/c", "/a/b") )
   assert( _PM.p4MatchesPath("/a/b/c", "/a/b/") )
   assert( _PM.p4MatchesPath("/a/b/c", "/a/b/c") )
   assert( not _PM.p4MatchesPath("/a/b/c", "/a/b/c/") )
end


function T.p4ParseInfo()
   eq( { ["a b"] = " c d", xxx = "y" },
       _PM.p4ParseInfo{ "a b:  c d", "xxx: y" } )
end


function T.p4GenClient()
   local cout = "b:\t name \n\na:\n\tline1\n\tline2\n\n"
   local cin = {
      "b",
      "a",
      b = " name ",
      a = { "line1", "line2" }
   }

   eq(cout, _PM.p4GenClient(cin))
end


function T.p4MapDir()
   local function mdr(a,b,c)
      return _PM.p4MapDir(a,b,c).result
   end

   -- basic syntax, quoting, special characters

   -- http://maillist.perforce.com/perforce/doc.082/manuals/cmdref/o.views.html
   -- Experimentation shows "%xx" is not supported in general; values other than
   -- 23, 25, 2A, and 40 are left as literals.  %2a is treated the same as %2A.
   -- This apparently makes '"' impossible to represent in a view.

   local view = {
      '//d/a/... //c/A/...',
      '//d/b/... "//c/B/..."',
      '//d/b%2a/... "//c/B%25/..."',
      '"//s/a b /d /..." "//c/S/..."',
   }
   eq("//c/A/x/",   mdr(view, "//d/a/x"))
   eq("//c/A/x/",   mdr(view, "//d/a/x/"))  -- trailing slash optional
   eq("//c/B/x/",   mdr(view, "//d/b/x"))
   eq("//c/B%/x/",  mdr(view, "//d/b*/x"))
   eq("//c/S/x/",  mdr(view, "//s/a b /d /x"))

   -- inclusion, exclusion, partial mappings, unsupported wildcards

   view = {
      "//d/x/... //r/XX/...",
      "-//d/x/y/... //r/XX/...",
      "//d/b/* //r/B/*",
      "//d/c/%%1/%%2/... //r/c/%%2/%%1/...",
      "//d/d... //r/e...",
      "//d/f/... //r/f/...",
   }
   eq("//r/XX/z/", mdr(view, "//d/x/z"))
   eq("//r/XX/z/", mdr(view, "//d/x/z/"))
   eq("//r/f/g/",  mdr(view, "//d/f/g"))
   eq("//r/f/",    mdr(view, "//d/f"))
   eq(nil,         mdr(view, "//d/x"))
   eq(false,       mdr(view, "//d/x/y"))
   eq(nil,         mdr(view, "//d/b"))
   eq(nil,         mdr(view, "//d/c/d/e/f"))  -- could do better...
   eq("//r/e/",    mdr(view, "//d/d"))
   eq("//d/f/x/",  mdr(view, "//r/f/x", true))

   -- reporting multiple matches

   view = {
      "//d/a/... //r/A/...",
      "//d/a/b/... //r/AB/...",
      "//d/a/c/... //r/AC/...",
   }
   eq({ {map="//d/a/... //r/A/...",result="//r/A/",subset="..."},
        {map="//d/a/b/... //r/AB/...", subset="b/..."},
        {map="//d/a/c/... //r/AC/...", subset="c/..."} },
      _PM.p4MapDir(view, "//d/a"))
   eq({ {map="//d/a/... //r/A/...",result="//r/A/x/",subset="..."},
        result = "//r/A/x/" },
      _PM.p4MapDir(view, "//d/a/x"))

   view = {
      "//d/a/... //r/A/...",
      "-//d/a/b/c/... //r/A/b/c/..."
   }
   eq({ {map="//d/a/... //r/A/...",result="//r/A/b/",subset="..."},
        {map="-//d/a/b/c/... //r/A/b/c/...",subset="c/..."},
        result = nil },
      _PM.p4MapDir(view, "//d/a/b"))


   -- Odd cases
   --
   -- A)  <depot>... <local>/...
   --
   --     Perforce will map <depot>/foo to <local>//foo [yes, two slashes].
   --     'p4 sync' will create a file <local>/foo without an error
   --     indication, but 'p4 edit foo' will not work when in that
   --     directory.  Depot paths, not local paths, must be used to edit,
   --     revert, etc..  Behavior on OSes other than Mac OS X is untested.
   --     p4MapDir() treats this as an unusable map.
   --
   -- B)  <depot>/... <local>...
   --
   --     This matches all the repository files, but spreads them out across
   --     multiple local directories.  We consider this unusable.

   view = {
      "//d/a/... //r/A...",    -- odd case, isn't it?
      "//d/A... //r/a/...",    -- odd case: what about A/x -> a//x ?
   }
   eq(nil,       mdr(view, "//d/a"))
   eq(nil,       mdr(view, "//d/A"))
   eq("//r/Ab/", mdr(view, "//d/a/b"))
   eq(nil,       mdr(view, "//d/A/b"))

   -- Overlays
   --
   -- We simply ignore overlay mappings.  A user can use this Perforce
   -- feature independently of pakman.

   local view = {
      '//d/a/... //c/A/...',
      '+//d/a/... "//c/myA/..."',
   }
   eq("//c/A/x/",   mdr(view, "//d/a/x"))
end

function T.p4ClientToLocal()
   local c2l = _PM.p4ClientToLocal
   eq("c:/a/b/c",  c2l("//workspace/b/c", "c:/a") )
   eq("c:/b/c",    c2l("//workspace/b/c", "c:/") )
   eq("/root/b/c", c2l("//w/b/c",         "/root") )
   eq("/r%1/b",    c2l("//w/b",           "/r%1") )
end


local testPkg = {
   uri = "p4://x/d/a@21",
   scheme = "p4",
   host = "xx",
   path = "/d/a",
   ver = "21"
}

local testClientTable = {
   "Client",
   "Host",
   "Root",
   "View",
   Client = "wksp",
   Host = "xx",
   Root = "/root",
   View = { "//depot/a/... //wksp/a/..." }
}

-- Mark up text file as it would be returned by "-s"
local function scriptify(str, prefix)
   prefix = prefix or "text"
   return str:gsub("([^\n]*\n?)", prefix..": %1").."\nexit: 0\n"
end

local testClientStr = _PM.p4GenClient( testClientTable )
local testClientReply = scriptify(testClientStr, "info")

local info = [[
info: Client name: <ROOT>
info: Client root: <ROOT>
info: Server address: xx:1666
exit: 0
]]

-- "Client root" needs to be valid; pm.lua checks for validity
local root = xpfs.getcwd()

function T.P4()
   local testCommands = {
      ["-s client %-o"] = testClientReply,
      ["-s info"] = info:gsub("<ROOT>", root),
      ["sync"] = "exit: 0\n",
      ["-s where %.%./a/%.%.%."] = "info: //depot/DA/... //client/foo/a/... /Users/joe/foo/a/...\nexit: 0\n"
   }

   local ts = TestSys:new(testCommands)
   local p4 = _PM.P4:new("p4", {}, ts)

   -- GetClient

   local c = p4:getClient()
   qt.match(ts.log, "%% p4 %-s client %-o\n")
   eq("xx", c.Host)
   eq({"//depot/a/... //wksp/a/..."}, c.View)
   -- same thing second time (no additional queries)
   c = p4:getClient()
   qt.match(ts.log, "%% p4 %-s client %-o\n")
   qt.match(c.Host, "xx")
   qt.match(qt.describe(c.View), qt.describe({"//depot/a/... //wksp/a/..."}))

   -- Map

   ts.log = ""
   local path = p4:createMap("/d/a", function() return {"/pakman/d/a"} end)
   eq(true, c.update)
   eq({"//depot/a/... //wksp/a/...","//d/a/... //wksp/pakman/d/a/..."}, c.View)
   eq(pathnorm(root.."/pakman/d/a"), pathnorm(path))
   qt.match(ts.log, "mapping")

   -- ApplyMaps

   p4:applyMaps()
   qt.match(ts.log, ".*%% p4 client %-i<<" .. pquote(testClientStr:sub(1,-2))
            .. "\t" .. c.View[2] .. "\n\n##\n")

   -- Sync

   ts.log = ""
   p4:sync("/d/a/...", 21)
   eq('% p4 -s sync //d/a/...@21\n', ts.log)

   -- Where
   eq( {scheme="p4", host="xx", path="/depot/DA"}, p4:where("../a"))
   -- Where: preserve trailing "/" so it's as siginificant in local names
   --        as in URIs (rules out treating it as a file)
   eq( {scheme="p4", host="xx", path="/depot/DA/"}, p4:where("../a/"))


   -- search AltRoots during initialize

   --   1. make "Root" in 'info' invalid
   testCommands["-s info"] = info:gsub("<ROOT>", root .. "_invalid")
   ts = TestSys:new(testCommands)
   p4 = _PM.P4:new("p4", {}, ts)
   eq(p4.clientRoot, root .. "_invalid")
   qt.match(ts.messages[1], "client root .* does not exist")

   --   2. provide AltRoots
   local arClient = clone(testClientTable)
   arClient.Root = root .. "_invalid"
   arClient[#arClient] = "AltRoots"
   arClient.AltRoots = {
      root .. "_invalid",
      root,
      root .. "_invalid2"
   }
   testCommands["-s client %-o"] = scriptify(_PM.p4GenClient(arClient), "info")
   ts = TestSys:new(testCommands)
   p4 = _PM.P4:new("p4", {}, ts)
   eq(p4.clientRoot, root)
   eq(#ts.messages, 0)
end


----------------------------------------------------------------
-- Shell tests
----------------------------------------------------------------

function T.Sys()
   local stdout = {}
   function stdout:printF(...)
      if bVerbose then
         print("stdout: " .. string.format(...))
      end
   end
   local os = _PM.Sys:new{ stdout = stdout }

   os.log = {}

   local text = ""
   function os.log:write(s)
      text = text .. s
      if bVerbose then
         print("log: " .. s)
      end
   end
   function os.log:printF(...)
      os.log:write(string.format(...))
   end

   local o = os:procRead('echo "hi"')
   qt.match(o, "hi")

   local tmpfile = workdir .. "/x.tmp"
   local a
   if o:match('"hi"') then
      -- DOS/Windows
      local dostmpfile = tmpfile:gsub("/", "\\")
      os:procWrite("sort > " .. dostmpfile, "This is a test\n")
      a = os:procRead("type " .. dostmpfile)
   else
      os:procWrite("cat > " .. tmpfile, "This is a test\n")
      a = os:procRead("cat " .. tmpfile)
   end

   eq("This is a test\n", a)
   assert(text ~= "")

   os:writeFile(tmpfile, "write\ntest")
   local f = io.open(tmpfile)
   eq("write\ntest", f:read"*a")
   f:close()

   assert(xpfs.remove(tmpfile))
end

----------------------------------------------------------------
-- Package tests
----------------------------------------------------------------

local deps1 = [[
  get { B= "p4://h/d/b@3" }
  min "deps.min"
  cmd "make"
]]


local function newSession(files)
   local me = {}
   function me:readFile(path)
      local t = files[path]
      if t then return t, path, path end
      print("newSession: could not load: " .. path .. " !")
   end
   me.sharedTables = {}
   return me
end

function T.DepFile()
   -- ProcessSpec
   local sess = newSession{
      ["p4://h/bar@1"] = deps1,
      ["p4://h/bar/baz/pak@1"] = deps1
   }

   local p = _PM.Package:new("p4://h/bar@1", TestSys:new(), nil, sess)
   eq({"p4://h/d/b@3"}, (map.xi"v")(p.deps))

   -- ReadSpec

   local ts = TestSys:new {
      ["-s print %-q //bar/baz/pak"] = scriptify(deps1),
      ["%-s client %-o"] = testClientReply,
      ["dirs //bar/baz"] = "info: //bar/baz\nexit: 0\n",
      ["%-s fstat"] = "exit: 0",
      ["%-s info"] = info:gsub("<ROOT>", root)

   }
   local p4 = _PM.P4:new("h", {}, ts)
   p = _PM.Package:new("p4://h/bar/baz/pak@1", ts, nil, sess)
   --p:visit( { GetPackage = function (_,u) return {uri = u } end } )
   --eq({"p4://h/d/b@3"}, (map.i"v.uri")(p.deps))
end



---------------------------------------------------------------
-- pm tests
----------------------------------------------------------------

function T.Get()
   --
   -- set up test environment
   --
   local myp4 = Object:new()
   local log = ""
   function myp4:createMap(path)
      log = log .. ":map " .. "h" .. ";" .. path
      return "/root" .. path
   end
   function myp4:applyMaps()
      if not self.apply then
         log = log .. ":apply"
         self.apply = true
      end
   end
   function myp4:fixVersion(u)
      return u or ""
   end
   function myp4:dirExists()
      return true
   end
   function myp4:sync(pattern, ver)
      log = log .. ":sync " .. pattern .. '@' .. ver
   end
   function myp4:readFile(path, ver)
      log = log .. ":rF"..path..(ver and "@"..ver or "")
      if path == "/d/a" then
         return nil
      end
      if path == "/d/b/..."
         or path == "/d/b"
         or path == "/d/b/pak" then
         return nil
      end
      eq("/d/a/pak", path)
      if path == "/d/a/pak" then
         return " get{B='p4://h/d/b@3'} ; min 'deps.min' ; mak 'xx.mak'  ", nil, path
      end
      return nil
   end
   function myp4:where()
   end

   myp4.scheme = "p4"
   myp4.host = "h"

   local os = TestSys:new()

   --
   -- Execute test
   --

   local testHandlers = { p4 = {} }
   function testHandlers.p4:getSession(scheme, host, path)
      return myp4
   end
   local pm = PM:new({handlers = testHandlers, hooks = {}}, os)
   pm:get("p4://h/d/a@21")

   log = log:gsub(":rF[^:]*", "")
   eq(":map h;/d/a/:map h;/d/b/:apply:sync /d/a/...@21:sync /d/b/...@3", log)

   assert(os.fs["/root/d/a/xx.mak"])
   assert(not os.fs["/root/d/b/deps.mak"])

   assert(os.fs["/root/d/a/deps.min"])


   --  \\server\name  -->  file://server/path

   local myfile = {}
   for k,v in pairs(myp4) do
      myfile[k] = v
   end
   myfile.scheme = "file"
   myfile.Where = _PM.File.Where
   testHandlers.file = {}
   function testHandlers.file:getSession(scheme, host, path)
      -- log = log .. ":gS"..scheme..";"..host
      return myfile
   end
   local fu_abspath, fu_isw = fu.abspath, fu.iswindows
   function fu.abspath(name)
      return fu_abspath(name:gsub("\\", "/"))
   end
   fu.iswindows = true

   log = ""
   local pm = PM:new({handlers = testHandlers, hooks = {}}, os)
   pm:visit([[\\h\d\b]])
   eq(":rF/d/b:rF/d/b/pak", log)

   fu.abspath = fu_abspath
   fu.iswindows = fu_isw
end


function T.vcsFile()
   -- file://server/path  -->  \\server\name
   local save = {fu.read, fu.iswindows}

   fu.iswindows = true
   function fu.read(name)
      return name
   end

   local f = _PM.File:new("file", "server")
   eq("//server/path", (f:readFile("/path")) )

   fu.read, fu.iswindows = table.unpack(save)
end


return qt.runTests()
