-- pm : package manager library
--
-- PM: PM (Package Manager) class implements 'get' and 'map' commands.
--     Instantiated per pakman invocation.  Maintains a cache of
--     previously-created VCS instances (indexed by scheme) and Package
--     instances indexed by URI).
--
-- VCS: Version Control System class implements VCS retrieval, mapping,
--     etc..  "P4" and "File" are the only VCS implementations.
--
-- VCS Sessions: Each VCS will create session objects.  There should be one
--     per Perforce workspace, so there is at least one per server.  The
--     session object retrieves files, describes mappings, etc.
--
-- Package: A Package objects describes a package (uri, dependencies and
--     other information garnered from the pakfile).
--

local Object = require "object"
local sysinfo = require "sysinfo"
local lpeg = require "lpeg"
local xpfs = require "xpfs"
local fsu = require "fsu"
local fu = require "lfsu"
local qt = require "qtest"
local pmlib = require "pmlib"
local pmload = require "pmload"
local pmuri = require "pmuri"
local map = require "cmap"
local memoize = require "memoize"
local xpexec = require "xpexec"
local errors = require "errors"

local insert, remove, concat = table.insert, table.remove, table.concat

------------------------------------------------
-- Utility functions
------------------------------------------------

local quoteArg = xpexec.quoteArg

local nixSplitPath = fsu.nix.splitpath  -- valid for URI paths as well


local function newReifyTable()
   return memoize.newTable(newReifyTable)
end

local uids = newReifyTable()


local function schop(path)
   if path:sub(-1) == "/" then
      return path:sub(1,-2)
   end
   return path
end


local function safeFormat(fmt, ...)
   local succ, txt = pcall(qt.format, fmt, ...)
   if not succ then
      txt = fmt:gsub("%%[a-zA-Z]", "?")
   end
   return txt
end


local function eprintf(...)
   io.stderr:write( qt.format(...) )
end
local LOG = qt.logvar

local function errorf(...)
   error(safeFormat(...),2)
end

local function beginsWith(str, prefix)
   return prefix == str:sub(1,#prefix)
end

local function plural(n)
   return n == 1 and "" or "s"
end

local function catFile(dir, file)
   if dir:sub(-1) ~= "/" then
      dir = dir .. "/"
   end
   return dir .. file
end

-- line(str) : Iterator over lines, handling CR, LF, or CRLF line endings.
--             Recognizes non-terminated final line.
-- usage:   for _,line in lines(str) do ... end
--
local function linesNext(txt,n)
   if n <= #txt then
      local line
      line,n = txt:match("([^\r\n]*)\r?\n?()", n)
      return n,line
   end
end
local function lines(txt)
   return linesNext, txt, 1
end

local function arrayIterFunc(a)
   local i = 0
   return function() i = i + 1 ; return a[i] end
end


-- Convert URI path to FS path
--
local function pathU2FS(path)
   return path:gsub("^/([a-zA-Z])[|:]", "%1:")
end

-- Convert FS path to URI path
--
local function pathFS2U(path)
   if fu.iswindows then
      path = path:gsub("\\", "/")
   end
   return path:gsub("^([a-zA-Z]):", "/%1:")
end

local function trimSlash(path)
   if path:sub(-1):match("[/\\]") and
      not (fu.iswindows and path:match("^%a:[/\\]$")) then
      path = path:sub(1,-2)
   end
   return path
end

local function dirExists(path)
   -- The Windows file operations require no slash at the end, except in the
   -- "<drive>:/" case.
   path = trimSlash(path)
   local st = xpfs.stat(path, "k")
   return st and st.kind == "d"
end


-- Replace occurrences of "#{name}" in 'str' with values from 'tbl', with "#"
-- and "\" quoted as necessary for make.
--
--    #{a}     ->   tbl.a
--    #{a.b}   ->   tbl.a.b
--    Array values are converted to space-delimited strings.
--
local function varExpand(str, tbl, where, err)
   err = err or function() end
   where = where or "string"
   local function expand(expr)
      expr = expr:match("{(.*)}")
      if expr == "#" then
         return expr
      end
      local val = tbl
      for name in ("."..expr):gmatch("%.([%a_][%w_]*)") do
         if type(val) ~= "table" or val[name] == nil then
            err("unknown variable reference #{%s} in %s", expr, where)
         end
         val = val[name]
      end
      if type(val) == "table" then
         val = concat(val, " ")
      end
      if val == nil then
         err("unknown variable reference #{%s} in %s", expr, where)
      end
      return val and tostring(val) or ""
   end
   local function mkExpand(str)
      -- quote for makefiles
      return ( expand(str):gsub("(\\*)#", "%1%1\\#") )
   end

   return ( str:gsub("#(%b{})", mkExpand) )
end


local function checkParams(params, schema)
   if type(schema) ~= "table" then
      error("schema value not a table", 2)
   end

   for name, typ in pairs(schema) do
      if typ.alias and params[typ.alias] and not params[name] then
         params[name] = params[typ.alias]
         params[typ.alias] = nil
      end
   end

   -- all parameters listed in schema must match schema
   for name, typ in pairs(schema) do
      if type(name) == "string" or type(name) == "number" then
         local val = params[name] or typ.default
         if val == "" and type(name) == "number" then
            val = typ.default
         end
         local values = typ.values or typ

         if val then
            local valid = #values == 0
            for _,pval in ipairs(typ.values or typ) do
               if pval == val then
                  valid = true
                  break
               end
            end
            if not valid then
               error( safeFormat('unsupported value %Q for %s', val, name), 2)
            end
         elseif not typ.optional then
            error( safeFormat('required parameter %Q not supplied', name), 2)
         end

         params[name] = val
      end
   end

   -- any params not listed in schema generate an error
   for name, value in pairs(params) do
      if not schema[name] then
         error( safeFormat('unsupported parameter %Q', name), 2)
      end
   end

   return table.unpack(params)
end

-- metatable to be used for 'params'
local mtCheckParams = { __call = checkParams }


-- Split URI "authority" field into domain name and port (use `defaultPort`
-- for port if port field was not present in `host`)
local function splitHost(host, defaultPort)
   local dn, port = host:match("([^:]*):?(.*)")
   if port == "" then
      port = defaultPort
   end
   return dn, port
end


-- Compute host address given base address.  Base acts as default, and
-- will also be used to resolve non-fully-qualified domain names.
--
local function p4MatchesHost(base, rel)
   local dnBase, portBase = splitHost(base, "1666")
   local dnRel, portRel = splitHost(rel, "1666")

   return ((dnRel == "" or beginsWith(dnBase.."..", dnRel.."."))
           and portRel == portBase )
end


-- Return true if path begins with 'pre'
--
local function p4MatchesPath(path, pre)
   return path==pre or beginsWith(path, pre) and
      (pre:sub(-1,-1)=="/" or path:sub(#pre+1,#pre+1) == "/")
end


----------------------------------------------------------------
-- Array class
----------------------------------------------------------------

local Array = Object:new()

Array.Append = insert -- for legacy PAK files

Array.append = insert
Array.concat = concat

function Array:map(f,...)
   local t = self:new()
   for _,x in ipairs(self) do
      t:append( f(x,...) )
   end
   return t
end

function Array:forEach(f,...)
   for _,x in ipairs(self) do f(x,...) end
end

function Array:initialize(t)
   if t then
      for _,x in ipairs(t) do
         self:append(x)
      end
   end
end

function Array:__call(...)
   insert(self, string.format(...))
end


------------------------------------------------
-- Sys: exposes OS services
------------------------------------------------

local Sys = Object:new()

function Sys:logF(...)
   self.log:printF(...)
end

function Sys:printF(...)
   self.stdout:printF(...)
end

function Sys:logLines(txt, prefix)
   if self.log.bActive then
      for _,line in lines(txt) do
         self.log:write(prefix..line.."\n")
      end
   end
end

-- Execute command and read output
function Sys:procRead(cmd)
   self:logF("%% %s >\n", cmd)
   local f = io.popen(cmd)
   local a = f:read("*a")
   f:close()
   self:logLines(a, "| ")
   return a
end

-- Execute command and feed it input
function Sys:procWrite(cmd, input)
   self:logF("%% %s <\n", cmd)
   self:logLines(input, "| ")
   local f = io.popen(cmd, "w")
   f:write(input)
   f:close()
end

-- Create/overwrite a file
function Sys:writeFile(fname, content)
   self:printF("writing %s\n", fname)
   self:logF("# writing file [%s]\n", fname)
   assert(fu.mkdir_p( (fu.splitpath(fname)) ))
   local f, err = io.open(fname, "w")
   if not f then
      error("fs: file error: " .. err)
   end
   f:write(content)
   f:close()
end

-- mdlib uses internal undocumented function (for an evil side-effect, at
-- that!) so we're stuck supporting older upper-case form
Sys.WriteFile = Sys.writeFile


function Sys:initialize(cfg)
   self.log = cfg.logFile
   self.stdout = cfg.stdout
end

--------------------------------
-- errMsg()
--------------------------------

local errMsgs = {}

errMsgs.badGlueKey = [[
*** Warning: in package file #{uri}
    'glue', which should be an array, has a non-numeric field: #{key}
]]

errMsgs.depotConflict = [[
*** Cannot map package without removing lines from client view; depot path
    appears to be partially mapped.
      Depot path = /#{path}/...
    Edit the client to map the package or remove these conflicting lines:
#{maps}
]]

errMsgs.depotExcludedError = [[
*** Package is mapped but partially unmapped; cannot map package without
    removing lines from client view; depot path appears to be partially
    mapped.
      Depot path = /#{path}/...
    Use the "--force" option to override and proceed anyway, or edit the
    client to map the package or remove these conflicting lines:
#{maps}
]]

errMsgs.depotExcludedWarning = [[
*** Package is mapped but partially unmapped; proceeding anyway due to
    "--force" option.
      Depot path = /#{path}/...
    Conflicts:
#{maps}
]]

errMsgs.clientConflict = [[
*** Cannot map package without removing lines from client view; client path
    appears to overlay other mappings.
      Depot path = /#{path}/...
      Client path = #{clientPath}/...
    Edit the client to map the package or remove these conflicting lines:
]]

errMsgs.badMapping = [[
*** Warning: mapping function returned invalid result.  Must be table of
    strings beginning with "/".  Use "--verbose" for more info.
]]

errMsgs.badHost = [[
*** p4 is configured for host #{p4host}
      p4 command = #{cmd}
      URI = p4://#{host}#{path}
]]

errMsgs.glueConflict = [[
*** Warning: glue file conflict.  Two packages require different contents.
      file name = #{path}
      package #1 = #{p1}
      package #2 = #{p2}
]]

errMsgs.nestedPkg = [[
*** Warning: nested roots!  One package's root directory is a parent
    of another.  See "Nested Roots" in the manual for more information.
      package #1 = #{top.uri}
            root = #{top.rootPath}
      package #2 = #{btm.uri}
            root = #{btm.rootPath}
]]

errMsgs.depsCycle = [[
*** Warning: circular dependencies!  This may result in errant 'mak' glue files
    and interfere with other features.  Chain of dependencies:
#{chain}
]]


errMsgs.legacy = [[
*** Warning: deprecated pakfile syntax: #{f}
]]

errMsgs.fileEdited = [[
*** Using locally edited #{path}
]]

errMsgs.fileNotInVCS = [[
*** Using local file not in VCS: #{path}
]]

errMsgs.badClientRoot = [[
*** Warning: client root directory does not exist.
      client name = #{clientName}
      client root = #{clientRoot}
]]

errMsgs.warnCygwin = [[
*** CYGWIN version of p4 client may cause problems!  Refer to the
    "Troubleshooting" section of the manual.
]]

local function errMsg(msgname, values, os)
   local msg = errMsgs[msgname]
   os:printF("%s", msg and varExpand(msg, values) or "*** " .. msgname .. "\n")
end

-----------------------------------------------
-- VCS Interface
--
--   vcs:where(path, ver) -> URI
--   vcs:readFile(path,ver) -> data, fsPath, uid
--   vcs:dirExists(path,ver) -> bool
--   vcs:createMap(path) -> fsPath
--   vcs:applyMaps()
--   vcs:sync()
--   vcs.host
--   vcs.scheme
----------------------------------------------

-----------------------------------------------
-- P4 class
-----------------------------------------------

local P4 = Object:new()

-- Parse fields from a p4 client description.  Returns 'client':
--   client[1..n] = names of values in the client
--   client[name] = value assigned to name:
--     single-line values =>  string
--     multi-line values  =>  array of strings
--
local function p4ParseClient(tbl)
   local client = {}
   local nextLine = arrayIterFunc(tbl)
   for line in nextLine do
      local name,tab,val = line:match("^(%w*):(\t?)(.*)")
      if name and (tab == "\t" or val == "") then
         if tab == "" then
            -- multi-line
            val = {}
            while true do
               local ll = nextLine()
               if ll and ll:sub(1,1) == "\t" then
                  insert(val, ll:sub(2))
               elseif ll and ll ~= "" then
                  -- bad termination of multi-line value
                  return nil, 'E1 (in "'..name..':")'
               else
                  break
               end
            end
         end
         insert(client, name)
         client[name] = val
      elseif line ~= "" and line:sub(1,1) ~= "#" then
         return nil, "E2 (unrecognized syntax)"
      end
   end
   return client
end

-- Accepts array of lines, returns { name -> value }
local function p4ParseInfo(tinfo)
   local map = {}
   for _,line in ipairs(tinfo) do
      local a,b = line:match("(.-): (.*)")
      if not a then
         a,b = line, ""
      end
      map[a] = b
   end
   return map
end


-- Generate textual form of a client from the table structure defined by
-- p4ParseClient.
--
local function p4GenClient(client)
   local o = Array:new()

   for _,key in ipairs(client) do
      local v = client[key]
      if not v then return nil end
      o:append(key..":")
      if type(v) == "string" then
         o:append("\t"..v)
      else
         for _,line in ipairs(v) do
            o:append("\n\t"..line)
         end
      end
      o:append("\n\n")
   end

   return o:concat()
end


-- viewLinePat: parse one line of a view into { minus, b1, wc1, b2, wc2 },
--   where b1/b2 are the portions of the file specs preceding the first
--   wildcard, and wc1/wc2 are the remainders of the file specs.
--
--   b1 & b2 are unquoted/unescaped.
--
--   Examples:
--      //foo/... //bar/...       -->   "", "//foo/", "...", "//bar/", "..."
--      -//f%40o/... "//b r/..."  -->  "-", "//f@o/", "...", "//b r/", "..."
--
local p4ViewPat do
   local C, P, R, S, Cs = lpeg.C, lpeg.P, lpeg.R, lpeg.S, lpeg.Cs

   local esc = P"%"/"" * (P"40"/"@" + P"23"/"#" + P"25"/"%%" + P"2"*S"aA"/"*")
   local base = (esc + 1) - (P"..." + "*" + "%%" * R"09")
   local uspec = Cs("//" * (base-" ")^0) * C( (1-P" ")^0 )
   local qspec = P'"' * Cs("//" * (base-'"')^0) * C( (1-P'"')^0 ) * P'"'
   local spec = qspec + uspec
   p4ViewPat = C(P"-"^-1) * spec * P" "^0 * spec
end


-- Find path in view
--
-- On entry:
--   view = View field of parsed client.  This is an array of strings, as in:
--         { "//depot/a/... //cl/a/...",  "-//depot/a/x/... //cl/a/x/..." }
--   dir = depot syntax for directory (e.g. "//depot/x/y/z")
--   reverse = if true, map from right to left (client to depot in a client view)
--
-- Returns table 'maps':
--
-- maps[1..n] = map objects, 'm', for each view line that influences the mapping
--      of files under 'dir'.
--
--    m.map    = line from client view
--    m.result = destination directory (if line was an inclusive match).  Only
--               maps[1] may have this field set, since an inclusive match overrides
--               any earlier lines in the view.
--    m.subset = subdirectories/patterns matched  (e.g. "a/b/...")
--               This is 'false' when the subset cannot be determined, and "..." for
--               inclusive matches.
--
-- maps.result =
--   string => destination directory; contents are mapped without conflicts.
--             This implies that #maps==1 and maps[1].result is a string.
--   false  => directory contents are entirely unmapped
--             This implies that #maps==0.
--   nil    => directory contents are mapped but not usable (or it is too
--             complicated to tell).
--             maps[1..#maps] contains partial and/or inclusive matches.
--
local function p4MapDir(view, dir, reverse)
   local dir = (dir:sub(-1,-1) == '/') and dir or dir..'/'
   local maps = {}
   local function partial(map, subset)
      insert(maps, { map=map, subset=subset } )
   end

   for _,map in ipairs(view) do
      local minus, base, wc, tobase, towc = p4ViewPat:match(map)
      if base then
         if reverse then
            base, wc, tobase, towc = tobase, towc, base, wc
         end
         if beginsWith(dir, base) then
            if wc == "..." then
               -- inclusive match
               if #base == #dir and tobase:sub(-1,-1) ~= "/" then
                  partial(map, false)   -- unusable "x/... x..." map
               else
                  if minus == "" then
                     local loc = tobase .. dir:sub(#base + 1)
                     if loc:match(".//") then
                        partial(map, wc)   -- unusable "x... x/..." map
                     else
                        maps = { { map=map, result=loc, subset=wc } }
                     end
                  else
                     maps = {}
                  end
               end
            elseif wc ~= "" then
               partial(map, false)  -- unsupported wildcard
            end
         elseif beginsWith(base, dir) then
            partial(map, base:sub(#dir+1)..wc)
         end
      end
   end

   if #maps == 1 and maps[1].result then
      maps.result = maps[1].result
   elseif #maps == 0 then
      maps.result = false
   end
   return maps
end


-- Encode [#@%*] as "%xx" sequences for p4 command args or client spec lines
--
local function p4Encode(str)
   return ( str:gsub("[#@%%%*]", pmuri.byteToHex) )
end

local p4Decode = pmuri.pctDecode

-- Generate pattern for this directory encoded for inclusion in a
-- client view map
local function p4DirPattern(dir)
   dir = p4Encode(dir .. "/...")
   if dir:match(" ") then
      dir = '"' .. dir .. '"'
   end
   return dir
end

-- Convert path from client syntax (//workspace/...) to local syntax (c:/...)
--
local function p4ClientToLocal(clientpath, root)
   return fu.resolve(root:gsub("\\","/"), clientpath:match("^//[^/]*/?(.*)"))
end


function P4:msg(msgname, values)
   errMsg(msgname, values, self.os)
end


function P4:initialize(cmd, cfg, os)
   self.cfg = cfg
   self.os = os
   self.readFileCache = {}
   self.scheme = "p4"
   self.cmd = cmd

   local vinfo = self.os:procRead(self.cmd .. " -V")
   local bcyg = vinfo and vinfo:match("CYGWIN")
   if bcyg then
      self:msg("warnCygwin")
   end

   local o = self:checkReadS("-s info")

   self.info = p4ParseInfo(o.info or {})
   if self.info["Client unknown."] then
      errorf("p4: Perforce client %Q has not been created.", self.info["Client name"])
   end

   self.host = self.info["Broker address"] or self.info["Server address"]
   if not self.host then
      error("p4: Error invoking p4; could not determine default host")
   end

   self.clientName = self.info["Client name"]
   if not self.clientName then
      error("p4: Error invoking p4; no 'client' on this server")
      self.clientName = "default"
   end

   self.host = self.host:gsub(":1666$", "")

   self.clientRoot = self.info["Client root"]
   if not self.clientRoot then
      errorf("p4: 'p4 info' reports no 'Client root' directory.")
   end

   if not dirExists(self.clientRoot) then
      -- search AltRoots
      local client = self:getClient()
      for _, dir in ipairs(client.AltRoots or {}) do
         if dirExists(dir) then
            self.clientRoot = dir
            break
         end
      end
      if not dirExists(self.clientRoot) then
         self:msg("badClientRoot", self)
      end
   end
end


-- P4VCS is a factory for P4 objects ("sessions")
--
local P4VCS = Object:new()

function P4VCS:initialize(cfg, os)
   self.sessions = {}
   self.sessionsByID = {}    -- index by [serverName,clientName]
   self.cfg = cfg.vcs.p4
   self.os = os

   cfg.vcs.p4.force = cfg.force

   -- `cmds` table maps server names to commands for invoking P4

   local cmds = self.cfg.command
   if not cmds then
      cmds = "p4"
   end
   if type(cmds) == "string" then
      cmds = { [""] = cmds }
   elseif not cmds[""] then
      cmds[""] = "p4"
   end
   -- backward compat with 0.92: vcs.p4.servers
   for k,v in pairs(self.cfg.servers or {}) do
      cmds[k] = v
   end
   self.cmds = cmds
end


-- Find/create session for scheme & host
--
--    host = hostname (or false if URI lists no hostname)
--
function P4VCS:getSession(scheme, host, path)
   host = host or ""

   -- Pick longest matching server name (empty host => use default)
   local bestKey, bestScore = "", 0
   for key, c in pairs(self.cmds) do
      local h, p = key:match("([^/]*)(.*)")
      local score = #h * 1000000 + #p
      if p4MatchesHost(host, h) and p4MatchesPath(path, p) and score > bestScore then
         bestKey = key
         bestScore = score
      end
   end

   -- Find/create session
   local cmd = self.cmds[bestKey]
   local s = self.sessions[cmd]
   if not s then
      s = P4:new(cmd, self.cfg, self.os)

      -- If this session points to the same server AND client as previously
      -- constructed ond, then re-use the already-created one and drop this
      -- one (otherwise client updates will be handled separately and maybe
      -- collide with each other).
      local uid = uids[s.host][s.clientName]
      local sDup = self.sessionsByID[uid]
      if sDup then
         s = sDup
      else
         self.sessionsByID[uid] = s
      end

      self.sessions[cmd] = s
   end

   -- Validate session
   if p4MatchesHost(s.host, host) then
      return s
   end

   -- HOST MISMATCH

   -- Maybe we can construct the appropriate P4 command by adding "-p"
   if not cmd:find(" %-p ") and host ~= "" then
      local domain, port = splitHost(host, 1666)
      local newcmd = cmd .. " -p " .. domain .. ":" .. port

      local function tryDashP()
         return P4:new(newcmd, self.cfg, self.os)
      end

      local e, s2 = errors.catch("p4: (.*)", tryDashP)
      if not e then
         -- save this away so we avoid this rigamarole next time
         self.cmds[s2.host] = newcmd
         return s2
      end
   end

   s:msg("badHost", {
            p4host=s.host,
            host=host,
            path = path,
            cmd = s.cmd
         })
   errorf("p4: Cannot connect to host '%s'.\n", host)
end


function P4:procWrite(args, input)
   return self.os:procWrite(self.cmd .. " " .. args, input)
end


function P4:getLatestCL()
   if not self.latest then
      local e, t = self:readS("-s changes -m 1 //...")
      self.latest = (t.info and t.info[1] or ""):match("Change (%d+) ")
      if not self.latest then error("p4: error invoking p4") end
   end
   return self.latest
end

function P4:getPathCL(path)
   local e, t = self:readS("-s changes -m 1 /" .. path)
   local cl = (t.info and t.info[1] or ""):match("Change (%d+) ")
   if not cl then error("p4: error invoking p4") end
   return tonumber(cl)
end


-- When retrieving file contents, always specify a version (this avoids
-- version skew between different packages).
--
function P4:fixVersion(ver)
   return ver~= "" and ver or self:getLatestCL()
end


-- Execute p4 command and read "-s"-style output into table of tag -> strings.
--
-- Example:
--    info: a
--    text: b
--    text: c
-- parses as:
--    { info = {"a"}, text = {"b", "c"} }
--
-- Returns: e, t
--    e = exit code (number) or nil
--    t = table of parsed data
--
function P4:readS(fmt, ...)
   local cmdline = string.format("%s "..fmt, self.cmd, ...)
   local txt = self.os:procRead(cmdline)

   local t = {}
   if txt then
      for _,line in lines(txt) do
         local key, value = line:match("([^%:]+)%: (.*)")
         if not key and line ~= "" then
            key = "text"  -- some p4 clients have exhibited this bug
            value = line
         end
         if key then
            if not t[key] then t[key] = {} end
            insert(t[key], value)
         end
      end
   end

   local exit = tonumber(t.exit and t.exit[1])
   return exit, t
end


-- CheckReadS: like ReadS, but asserts exit code of 0.
-- Returns: table of tags->lines
--
function P4:checkReadS(...)
   local e, t = self:readS(...)
   if e ~= 0 then
      for _,e in ipairs(t.error or {}) do
         self.os:printF("p4: %s\n", e)
      end
      error("p4: error invoking p4")
   end
   return t
end


-- Return local file path that is mapped to depot path 'path'
--
function P4:depotToLocal(path)
   local client = self:getClient()
   local maps = p4MapDir(client.View, "/"..path)
   return maps.result and p4ClientToLocal(maps.result, self.clientRoot)
end


-- Get the contents of a file in VCS.  If there is a local checked-out copy
-- that has been edited, return the local copy.
--
-- Returns: data, lpath, uid   [all are nil on failure]
--   data  = contents of file (string)
--   lpath = local fs path (string) if local copy was returned
--
function P4:readFile(path, ver)
   -- see if it is opened for edit/... locally
   local lpath = self:depotToLocal(path)
   local name = p4Encode(path) .. "@" .. self:fixVersion(ver)
   local result = self.readFileCache[name]
   if result then
      return result[1], result[2], result
   end

   local st = lpath and xpfs.stat(lpath, "p")
   local writable = st and st.perm:sub(2,2) == "w"

   if not writable then
      -- no local writable copy => try server
      local e, t = self:readS('-s print %s', quoteArg("/"..name))

      -- For deleted files, "p4 print" will not display an error, but it
      -- will omit an info string, so we take the absence of "info:" to mean
      -- that the file does not exist.

      if e == 0 and not t.error and t.info then
         local data = ""
         if t.text then
            data = concat(t.text, "\n") .. "\n"
         end
         result = {data}
      end
   end

   if not result and st then
      -- use local file
      local str = fu.read(lpath)
      if str then
         self:msg((writable and "fileEdited" or "fileNotInVCS"), {path=lpath})
         result = {str, lpath}
      end
   end

   result = result or {}
   self.readFileCache[name] = result
   return result[1], result[2], result
end


-- Return true if a directory exists at 'path' and 'ver'
--
function P4:dirExists(path, ver)
   local dirname = quoteArg("/" .. p4Encode(schop(path)) .. "@" ..self:fixVersion(ver))
   local e, t = self:readS('-s dirs %s', dirname)
   local exists = e == 0 and t.info and not t.error

   if not exists then
      local lpath = self:depotToLocal(path)
      if lpath and dirExists(lpath) then
         exists = true
      end
   end
   return exists
end


-- Return a parsed client structure
--
function P4:getClient()
   if not self.client then
      local t = self:checkReadS("-s client -o")
      if not t.info then
         errorf("p4: no valid Perforce client")
      end
      local c, err = p4ParseClient( t.info )
      if not c then
         errorf("p4: parsing %s client, error %s", err)
      end
      -- when View is empty it will be missing entirely
      if not c.View then
         insert(c, "View")
         c.View = {}
      elseif type(c.View) == "string" then
         errorf("p4: client View is a string, not a list")
      end
      self.client = c
   end
   return self.client
end


-- Locate package in local mapping, adding if necessary to the in-memory client.
--
-- Return local FS path to directory, or nil,
--
function P4:createMap(path, fmap)
   -- get clientspec
   local client = self:getClient()
   local view = client.View

   path = schop(path)

   -- see if it is present in the clientspec
   local maps = p4MapDir(view, "/"..path)
   local clientPath = maps.result

   -- if not present, add it
   if maps.result == nil then
      local t = {}
      for _,m in ipairs(maps) do
         if not m.result then
            insert(t, "      " .. m.map)
         end
      end
      local mapText = concat(t, "\n")
      if maps[1] and maps[1].result then
         if self.cfg.force then
            self:msg("depotExcludedWarning", {path=path, maps=mapText})
            clientPath = maps[1].result
         else
            self:msg("depotExcludedError", {path=path, maps=mapText})
            error("p4: package unusably/partially mapped.")
         end
      else
         self:msg("depotConflict", {path=path, maps=mapText})
         error("p4: package unusably/partially mapped.")
      end
   elseif maps.result then
      self.os:logF("# existing map: %s -> %s\n", path, tostring(maps.result))
   else
      -- add to view

      local function pathIsOkay(cpath)
         local maps = p4MapDir(view, "//"..client.Client..cpath, true)
         return maps.result == false, maps
      end

      self.os:logF("# mapping '%s'\n", path)

      -- Call package-supplied 'mapping' function if provided.  This returns
      -- a list of paths rooted at the client root.

      local lpaths = fmap()
      self.os:logF("%s", qt.format("# mapping function returned: %Q\n", lpaths))
      if type(lpaths) ~= "table" or not lpaths[1] then
         self:msg("badMapping")
         error("p4: error mapping packge")
      end

      -- Find first usable path in package-provided list (if any)

      local cpath, okay, maps
      for _,p in ipairs(lpaths) do
         if type(p) ~= "string" or p:sub(1,1) ~= "/" then
            self:msg("badMapping")
            error("p4: error mapping package")
         elseif not okay then
            cpath = p
            okay, maps = pathIsOkay(p)
            self.os:logF("# location '%s' is %s\n", tostring(cpath),
                         okay and "available" or "unavailable")
         end
      end

      -- Try finding an unused name with "-<n>" suffixes.  The purpose is to
      -- "step around" conflicting mappings that Pakman may have created in
      -- the past.  We cannot guarantee success; some clients leave no room
      -- for any new mappings without shadowing or removing existing lines.
      --
      if not okay then
         for n = 2, 99 do
            local p = cpath .. "-" .. n
            okay, maps = pathIsOkay(p)
            if okay then cpath = p ; break end
         end
      end

      clientPath = "//" .. client.Client .. cpath
      if not okay then
         self:msg("clientConflict", {path=path, clientPath=clientPath})
         for _,m in ipairs(maps) do
            self.os:printF("      %s\n", m.map)
         end
         error("p4: client path conflict")
      end

      self.os:printF("mapping /%s\n", path)
      local map = string.format("/%s/... %s/...", p4Encode(path), p4Encode(clientPath))
      local map = p4DirPattern("/"..path) .. " " .. p4DirPattern(clientPath)
      insert(view, map)
      client.update = true  -- flag for update
   end

   return p4ClientToLocal(clientPath, self.clientRoot)
end


-- Update clients that have been modified
--
function P4:applyMaps()
   local client = self.client
   if client.update then
      self.os:printF("updating client %s\n", client.Client)
      self:procWrite("client -i", p4GenClient(client))
      client.update = false
   end
end


-- Sync a package to a particular version
--
function P4:sync(pattern, ver)
   local path = pattern .. "@" .. self:fixVersion(ver)
   self.os:printF("syncing p4://%s%s\n", self.host, path)

   local opts, flags = "", {}
   for f in concat(self.cfg.sync or {}):gmatch("[^ ]") do
      if not f:match("[fknp]") then
         errorf("p4: bad flag specified via --p4-sync: '%s'", f)
      elseif not flags[f] then
         flags[f] = true
         opts = opts .. " " .. quoteArg("-" .. f)
      end
   end

   local t = self:checkReadS('-s sync%s %s', opts, quoteArg("/" .. path))
   if t.info then
      self.os:printF(" [%d changes]\n", #t.info)
   end
end

-- Sync a package to a particular version
--
function P4:show(pattern, ver)
   local path = pattern .. "@" .. self:fixVersion(ver)
   self.os:printF("p4://%s%s\n", self.host, path)
end


-- Return absolute package location, given local path
--
--
function P4:where(fsPath)
   -- 'p4 where' returns error when path is at the top of a map...
   --     Client:   //depot/path/...   //client/path/...
   --     cd path
   --     p4 where . -> error
   --     p4 where dummy -> success
   -- It sometimes reports "exit: 0" and "error: ??? - file(s) not in client view"
   --
   -- "foo" could refer to a directory or file named foo.  If a directory,
   -- then "foo/..."  might be mapped while "foo..." is not completely
   -- mapped, so we should append "/...".  This also works for files, since
   -- "file/..."  should also be mapped if "file" is mapped.  We need

   local suffix = fsPath:sub(-1) == "/" and "..." or "/..."
   local e, t = self:readS('-s where %s', quoteArg(p4Encode(fsPath) .. suffix))
   if e ~= 0 then
      return false
   end

   -- When the local path is mapped more than once (i.e. some view lines
   -- shadow previous lines) the shadowed lines are ALSO returned, but with
   -- an initial "-".

   local depotPath
   for _, line in ipairs(t.info or {}) do
      depotPath = line:match("^/(/.-) //")
      if depotPath then break end
   end

   if depotPath and depotPath:sub(-#suffix) == suffix then
      depotPath = p4Decode(depotPath) -- depot path is p4 encoded
      return { scheme="p4", host=self.host, path=depotPath:sub(1,-1-#suffix) }
   end
   return false
end


----------------------------------------------------------------
-- File
----------------------------------------------------------------

local File = Object:new()

function File:initialize(scheme, host)
   host = host or ""
   self.prefix = ""
   if host ~= "" then
      self.prefix = "//"..host
      if not fu.iswindows then
         error("pm: Invalid host field for 'file:' URI: " .. host)
      end
   end
   self.host = host
   self.scheme = scheme
   self.uids = memoize.newTable(function() return {} end)
end

-- convert URI path to file name
function File:u2FS(path)
   return self.prefix .. pathU2FS(path)
end

function File:readFile(path, ver)
   local fsPath = self:u2FS(path)
   local str = fu.read(fsPath)
   return str, fsPath, self.uids[path]
end

-- Return true if a directory exists at 'path' and 'ver'
--
function File:dirExists(path, ver)
   -- trailing "/" okay with FS APIs
   return dirExists(self:u2FS(path))
end

function File:createMap(path)
   return self:u2FS(path)
end

function File:applyMaps(path)
end

function File:sync(path)
end

function File:where(fsPath)
   local host, path = fsPath:match("^[/\\][/\\]([^/\\]*)(.*)")
   if not host then
      path = fu.abspath(fsPath)
   end
   return {scheme="file", host = host, path=pathFS2U(path)}
end

function File:fixVersion(ver)
   return ver or ""
end

local FileVCS = Object:new()

function FileVCS:initialize()
   self.hosts = {}
end

function FileVCS:getSession(scheme, host, path)
   local t, k = self.hosts, host or ""
   if not t[k] then
      t[k] = File:new(scheme, host)
   end
   return t[k]
end

----------------------------------------------------------------
-- GlueTypes
----------------------------------------------------------------

local GlueTypes = {}

local minTemplate = [[
# pakman min file

#{defs}

# adjust paths to be relative to current working dir
_pkg_deps = #{vars}
__pkg_dir := $(filter-out ./,$(dir $(lastword $(MAKEFILE_LIST))))
$(foreach v,$(_pkg_deps),$(eval $v := $(__pkg_dir)$$($v)))

# assign these variables only for the top-level makefile
ifeq ($(origin __pkg_root),undefined)
  __pkg_root    := $(__pkg_dir)#{toroot}
  __pkg_result  := $(__pkg_root)$(filter-out /.,/#{pkg.expanded.result})
  __pkg_deps    := $(_pkg_deps)
endif
__pkg_uri     ?= #{pkg.uri}
__pkg_version ?= #{pkg.version}

]]


-- Generate make include file that provides the locations of dependencies
--
function GlueTypes.min(pkg, g)
   local m = pkg:getExpandEnv(g.fsDir)

   -- add MIN-specific variables to expand environment
   m.glueFile = g
   m.vars = Array:new()
   m.defs = Array:new()
   for name,p in pairs(pkg.children) do
      m.vars:append( name )
      m.defs:append( name .. " = " .. m.paths[name] )
   end
   m.defs = m.defs:concat( "\n" )

   local o = type(g.template) == "string" and g.template or
             type(g.template) == "function" and g.template(m, minTemplate) or
             minTemplate
   o = o:gsub("^%+", minTemplate)

   return pkg:expandString(o, m, "MIN file template")
end


local makTemplateBase = [[
# pakman tree build file
_@ ?= @

#{rules}
]]


local makJobdef = [[
job = $(_@)echo $3 && $(if $1,cd $1 && )$2
]]


-- makJobdefNeat:
--
--   Displays one line per sub-package when building, unless an error occurs.
--
--   In CMD, 'cd' affects subsequent commands, so we use an absolute path
--   for the log file.
--
local makJobdefNeat = [[
W := $(findstring ECHO,$(shell echo))# W => Windows environment
@LOG = $(if $W,$(TEMP)\\)$@-build.log

C = $(if $1,cd $1 && )$2
job = $(_@)echo $3 && ( $C )> $(@LOG) && $(if $W,del,rm) $(@LOG) || ( echo ERROR $3 && $(if $W,type,cat) $(@LOG) && $(if $W,del,rm) $(@LOG) && exit 1)
ifdef VERBOSE
  job = $(_@)echo $3 && $C
endif
]]


-- Generate mak glue file
--
-- The mak glue for a package builds all of its dependencies and the package
-- itself, in the proper order.
--
-- The mak file contains a makefile target for each package build.  Each
-- target builds that package and its sub-tree.  Ordering is controlled by
-- naming pre-requisites, not by generating sequences of commands (scripts)
-- to build each target.  This allows the user to use make's "-j" option for
-- parallel builds if that works for their project tree.
--
-- The top target is called "tree", and other targets are assigned the names
-- their parent packages use in `packge.deps`, unless there is a conflict.
-- Child names may collide with other child names or pre-assigned names
-- (e.g. "tree").
--
-- Redundant commands:
--
--    When multiple child packages share the same root directory AND the
--    same make command, the mak file should place the command in a single
--    target so it will not be issued twice.  (Note: empty make commands are
--    simply ignored.)  Before doing so we make sure that the packages have
--    the same set of dependencies, because otherwise we could introduce a
--    circular dependency that was not there originally.  This seems odd,
--    since that would require two variants to have the same build command
--    and root but different dependencies.  But that could occur when
--    *semi-transparent* variants commingle results.  (Fully transparent
--    packages are not a concern since we ignore empty commands.)  A
--    practical (?) example:
--
--       tools?lua requires LUATOOL
--       LUATOOL   requires tools?c
--
--    If 'tools' has its own build step independent of its dependencies, and
--    re-exposes those dependencies via distinct glue files, then the above
--    configuration could actually work and produce consistent results
--    (despite flaunting "guidelines").  While there may be external reasons
--    to "outlaw" the above arrangement, they may not be universally
--    applicable, and anyway the mak file generation step itself does not
--    need to impose any such restrictions on the rest of the system.  The
--    simple solution here is to leave such packages (and redundant
--    commands) as different targets.


-- Convert a name to a legal make target name: encode characters
-- syntactically significant in targets or pre-requisites.
local function makeByteToHex(c)
   return string.format("^%02X", string.byte(c))
end
local function quoteMakName(name)
   return name:gsub("[:%s=#\\%%|%$%^]", makeByteToHex)
end


-- createTargets: Construct array of makefile targets for a package tree.
-- Skip packages that have no build steps and no descendants with build
-- steps.  Coalesce targets that have the same directory, commands, and
-- dependencies.
--
-- Each target = { name, prereqs, dir, make, clean }
--
local function createTargets(pkgTop)
   local targets = {}
   local names = {}
   local equivs = {}

   -- visit()
   --   p = package, name = suggested name, parent = parent name
   --   Returns false if package can be skipped, target name otherwise
   local visit, _visit

   function _visit(p, name, parent)
      -- find a unique name for this target
      name = name:gsub("_clean$", "_clean_")
      while names[name] do
         name = parent .. "_" .. name
         parent = ""
      end
      names[name] = p

      -- get prerequisites
      local prereqs = {}
      for childName, child in pairs(p.children) do
         local childName = visit(child, childName, name)
         insert(prereqs, childName or nil)
      end

      if not (p.expanded.commands.make or prereqs[1] or name=="tree") then
         -- omit this package from the tree
         return false
      end

      -- generate a target for this package
      local t = {
         make = p.expanded.commands.make,
         clean = p.expanded.commands.clean,
         prereqs = prereqs,
         name = quoteMakName(name),
         dir = p.fsRoot and fu.relpathto(pkgTop.fsRoot, p.fsRoot),
      }

      -- detect redundant make commands & coalesce with other targets
      local prereqs = concat(t.prereqs, " ")
      local uid = uids[t.make or ""][t.clean or ""][t.dir or ""][prereqs]
      if equivs[uid] then
         return equivs[uid]
      end
      equivs[uid] = t.name

      insert(targets, t)
      return t.name
   end

   local visited = {}
   function visit(p, name, parent)
      if visited[p] == nil then
         visited[p] = _visit(p, name, parent)
      end
      return visited[p]
   end

   visit(pkgTop, "tree")

   return targets
end


function GlueTypes.mak(pkgTop, g)
   -- Provide command to invoke this `mak` file (unless PAK has overridden)
   if not pkgTop.expanded.commands.maketree then
      pkgTop.expanded.commands.maketree = "make -f " .. g.path
   end

   -- get graph of targets
   local targets = createTargets(pkgTop)

   -- output makefile to build targets
   local o = Array:new()

   local names = (map.i"v.name")(targets)
   local cleanNames = (map.i"v .. '_clean'")(names)
   o(".PHONY: %s %s", concat(names, " "), concat(cleanNames, " "))
   o("")

   -- traverse from end so 'tree' will be first
   for ndx = #targets, 1, -1 do
      local t = targets[ndx]
      local cdDir = t.dir:gsub("^%.$", "")
      o("%s: %s", t.name, concat(t.prereqs, " "))
      if t.make then
         o("\t$(call job,%s,%s,making %s)", cdDir, t.make, t.dir)
      end
      o("")

      o("%s_clean: %s", t.name, concat((map.i"v..'_clean'")(t.prereqs), " "))
      if t.clean then
         o("\t$(call job,%s,%s,cleaning %s)", cdDir, t.clean, t.dir)
      end
      o("")
   end

   local venv = pkgTop:getExpandEnv(g.fsDir)
   venv.rules = concat(o, "\n")
   local tmpl = makTemplateBase .. (g.verbose and makJobdef or makJobdefNeat)

   return pkgTop:expandString(tmpl, venv, "MAK file template")
end


----------------------------------------------------------------
-- Package
----------------------------------------------------------------

-- Package objects contain fields documented in the reference.
--
-- The constructor also assigns:
--    os        = utility IO functions
--    pm        = package manager
--    parent    = a parent package (one of potentially many)
--    turi      = table form of URI
--    rootPath  = root.path without trailing "/"
--
-- Other fields are assigned later:
--    children  =  { <name> -> <package> }
--    fsRoot    = absolute path to root in FS
--    fsResult  = absolute path to result in FS
--    expanded  = expanded versions of strings (expanded.result,
--                expanded.commands.*)

local Package = Object:new()


function Package:initialize(uri, os, parent, pm)
   self.uri      = uri           -- name ends in "/<file>" or "/..."
   self.turi     = pmuri.parse(uri)
   self.os       = os
   self.parent   = parent
   self.pm       = pm

   function self.error(fmt, ...)
      errorf("pm: Error in package file: %s\n"..fmt, self.uri, ...)
   end

   -- These properties can be seen/modified by package files:

   local pkg = {}
   pkg.uri      = uri
   pkg.glue     = Array:new()   -- min/mak/etc. files to emit
   pkg.commands = {}
   pkg.root     = "."
   pkg.deps     = {}            -- name -> URI
   pkg.children = {}            -- name -> package
   pkg.result   = "."
   pkg.files    = { "..." }
   pkg.params = self.turi.params or {}

   setmetatable(pkg.params, mtCheckParams)

   local plain = self.turi.path:sub(-4) == "/..."

   if not plain then
      pkg = self:processSpec(pkg)
   end

   pkg.uri = nil
   for k,v in pairs(pkg) do
      self[k] = pkg[k]
   end

   self.turi.params = self.params
   self.uri = pmuri.gen(self.turi)

   local rootLoc = pmuri.parse(self.root, uri)
   rootLoc.path = catFile(rootLoc.path, "")
   self.root = pmuri.gen(rootLoc)
   self.rootPath = schop(rootLoc.path)      -- documented export

   -- Locate fragment
   local frag = self.turi.fragment or ""
   if frag ~= "" then
      if frag:match"^/" or frag:match"^../" or frag:match"//" then
         errorf("pm: bad fragment in %s", self.uri)
      end
      self.result = catFile(self.result, frag)
      if plain then
         self.files = { frag .. "..." }
      end
   end

   if type(self.glue) ~= "function" then
      self:validateGlue()
   end

   -- Dump package for debugging

   self.os:logF("# Package %s = {\n", self.uri)
   for _,fld in ipairs{"name","deps", "glue", "commands", "root", "result",
                       "files", "rootPath", "ver"} do
      self.os:logF("#    %s = %s,\n", fld, qt.describe(self[fld]))
   end
   self.os:logF("# }\n", self.uri)
end


-- Global table for user files: Loaded/required files have this set as their
-- environment.  PAK files have a package object set as their environment,
-- but it delegates __index to this table.
--
-- This does not strictly sandbox the user executables, since they can
-- modify tables like 'string' and 'math', and they can obtain the original
-- global via getfenv.
--
local userGlobals = {}
for k,v in pairs(_G) do
   userGlobals[k] = v
end
userGlobals._G = userGlobals
userGlobals.sys = require "sysinfo"
userGlobals.pmlib = require "pmlib"


-- These functions are defined for compatibility with older versions of pakman.
--
local function defLegacyFuncs(locals, penv, os)
   function locals.min(f)
      errMsg("legacy", {f="min"}, os)
      penv.glue:append({type="min", path=f})
   end
   function locals.mak(f)
      errMsg("legacy", {f="mak"}, os)
      penv.glue:append({type="mak", path=f})
   end
   function locals.get(t)
      errMsg("legacy", {f="get"}, os)
      for k,v in pairs(t) do
         penv.deps[k] = v
      end
   end
   function locals.cmd(make, clean)
      errMsg("legacy", {f="cmd"}, os)
      penv.commands.make = make
      penv.commands.clean = clean
   end
end


-- Validate glue entries & supply defaults
--
function Package:validateGlue()
   local glue = self.glue
   for ndx,g in ipairs(glue) do
      if type(g) == "string" then
         g = { path = g }
         glue[ndx] = g
      end
      if type(g) ~= "table" or
         type(g.path) ~= "string" or
         type(g.type or "") ~= "string"
      then
         self.error("glue[%d] is invalid: %Q\n", ndx, g)
      end
      if not g.type then
         g.type = g.path:match("[^/%.]*$"):gsub(".*[Mm]akefile$", "mak")
      end
   end
   for k,v in pairs(glue) do
      if type(k) ~= "number" then
         errMsg("badGlueKey", { uri=self.uri, key=tostring(k) }, self.os)
      end
   end
end


-- Process package description file contents.  Append dependencies to uriList.
--
function Package:processSpec(pkg)
   local perror = self.error

   local pak, pakfile, pakuid = self.pm:readFile(self.uri)
   if not pak then
      perror("Could not load file")
   end

   -- instances of the same pakfile share the same 'shared' table
   pkg.shared = self.pm.sharedTables[pakuid]

   local penv = {}
   for k,v in pairs(pkg) do
      penv[k] = v
   end
   setmetatable(penv, { __index = userGlobals })

   local filename = pakfile or select(2, nixSplitPath(self.turi.path) )

   -- Get instances of 'require', 'loadstring', etc., tailored to this package's URI
   -- Values in 'locals' will manifest as local variables to the package file
   local function pmread(uri)
      return self.pm:readFile(uri)
   end
   local locals = pmload.pmfuncs(self.uri, pmuri.gen, pmread, nil, userGlobals)

   defLegacyFuncs(locals, penv, self.os)
   locals.self = penv

   local pakf, err = pmload.loadstringwith(pak, "@"..filename, locals, penv)
   local succ = false
   if pakf then
      succ, err = pcall(pakf)
   end
   if not succ then
      perror("%s", tostring(err))
   end

   -- If pakfile returns a value, use that as the package description
   if type(err) == "table" then
      penv = err
      for k,v in pairs(pkg) do
         if penv[k] == nil then
            penv[k] = v
         end
      end
   elseif err then
      perror("package returned value of type %s; should be nil or table",
              type(err))
   end

   -- Validation and post-processing

   local optionalFields = {
      mapping = {"function"},
      redir = {"string", "table"},
      message = {"string", "function"},
      glue = {"table", "function"},
   }

   for var,val in pairs(pkg) do
      local expected = optionalFields[var] or {type(val)}
      for _,ty in ipairs(expected) do
         if type(penv[var]) == ty then
            expected = nil
            break
         end
      end
      if expected then
         perror("%s is a %s value (should be a %s)",
                 var, type(penv[var]), concat(expected, " or "))
      end
   end

   for k,v in pairs(penv.deps) do
      if type(v) == "table" then
         penv.deps[k] = pmuri.gen(v)
      end
      if type(k) ~= "string" or type(penv.deps[k]) ~= "string" then
         perror("deps contains an invalid entry: %Q.\nIt should map strings "
                 .. "to URIs in string or table form.", {[k]=v} )
      end
   end

   local bWarned = false
   for var,val in pairs(penv) do
      if pkg[var] == nil and not optionalFields[var] then
         if not bWarned then
            self.os:printF("*** Warning: in package file %s ...\n", self.uri)
            self.os:printF("***   Use 'local' keyword to declare local variables\n")
         end
         self.os:printF("***   unknown global variable: %s\n", tostring(var))
         bWarned = true
      end
   end

   for ndx, pat in ipairs(penv.files) do
      local p2 = fu.cleanpath(pat)
      penv.files[ndx] = p2

      -- Initial "/" or ".." would produce unpredictable results, since
      -- mapping is not guaranteed.
      if p2:sub(1,3) == "../" or p2 == ".." or p2:sub(1,1) == "/" then
         perror("Pattern in 'files' is not child directory: %s\n", pat)
      end
   end

   -- Redirection

   if penv.redir then
      local predir = self.pm:getPackage(penv.redir, self.uri, self)
      for k,v in pairs(predir) do
         penv[k] = v
      end
      penv.parent = nil   -- don't blow away our own
      penv.redirs = penv.redirs or {}
      insert(penv.redirs, self.uri)
   end

   return penv
end


local function inherit(pkg, prop)
   while pkg do
      if pkg[prop] ~= nil then
         return pkg[prop]
      end
      pkg = pkg.parent
   end
end


function Package:getMapping()
   return inherit(self, "mapping")
end


-- Create a varExpand environment table for a given package and current dir.
-- This defines variables common to all templated strings:
--   #{pkg} = the package itself
--   #{paths.childName} = relative path to result directory for child
--
function Package:getExpandEnv(basedir)
   basedir = basedir or "."
   local env = {
      pkg = self,
      paths = {},    --  name -> relative path
   }
   for name,child in pairs(self.children) do
      -- With circular dependencies, child.fsResult might be nil.

      env.paths[name] = fu.relpathto(basedir, child.fsResult or
                                     fu.resolve(child.fsRoot, child.result))
   end
   env.toroot = fu.relpathto(basedir, self.fsRoot)
   return env
end


function Package:expandString(str, env, where)
   if type(str) == "function" then
      str = str(env)
      if type(str) ~= "string" then
         self.error("Function '%s' did not return string", where or "?")
      end
   else
      str = varExpand(str, env, where, self.error)
   end
   return str
end


-- Expand/evaluated fields that are templates or functions
--    commands.*
--    result
--
function Package:expandFields()
   local venv = self:getExpandEnv(self.fsRoot)

   local e = { commands = {} }
   local ec = e.commands
   self.expanded = e

   e.result = self:expandString(self.result, venv, "result")

   for k,v in pairs(self.commands) do
      ec[k] = self:expandString(self.commands[k], venv, "commands."..k)
   end

   -- provide default for 'clean' if 'make' is defined
   if ec.make and not ec.clean then
      ec.clean = ec.make .. " clean"
   end

   if type(self.glue) == "function" then
      self.glue = self.glue(venv)
      self:validateGlue()
   end
end


function Package:genGlue()
   for _,g in ipairs(self.glue) do
      g.uri = self.uri
      g.fsPath = fu.resolve(self.fsRoot, g.path)
      g.fsDir  = fu.splitpath(g.fsPath)
      function g:relPathTo(p)
         return fu.relpathto(self.fsDir, p)
      end

      local fn = GlueTypes[g.type]
      if fn then
         g.data = fn(self, g)
      else
         self.os:printF("*** Warning: unknown glue file type [%s]\n", tostring(g.type))
      end
   end
end


function Package:writeGlue(written)
   for _,g in ipairs(self.glue) do
      local data, path = g.data, g.fsPath
      if data then
         local g1 =written[path]
         if g1 and data ~= g1.data then
            errMsg("glueConflict", { path=path, p1=g1.uri, p2=g.uri}, self.os)
         end
         self.os:writeFile(path, data)
         written[path] = g
      end
   end
end


----------------------------------------------------------------
-- Syncs
----------------------------------------------------------------
--
-- A Syncs instance is a collection of subtrees in the repository that are
-- pending retrieval.  Each subtree is described by a pattern string.

local Syncs = Object:new()

function Syncs:initialize()
   self.lists = {}   -- indexed by vcs instance
end


-- Add a repository subtree to the set.
--
-- Each vcs instance is specific to an individual host, so vcs + path + ver
-- is complete.
--
function Syncs:add(vcs, path, ver)
   local list = self.lists[vcs]
   if not list then
      list = Array:new()
      self.lists[vcs] = list
   end

   -- sort <p>... before <p>
   local sort, tail = path:match("(.-)%.%.%.(.*)")
   if not sort then
      sort, tail = path.."\1", ""
   end

   list:append{ path = path, ver = ver, sort = sort, tail = tail }
end


-- Coalesce syncs and flag version conflicts.
--
-- Example: "/a/..." overlaps "/a/b/...".  If the versions differ they
-- conflict.  If the versions are the same or b is don't care (have), "/a/b/..." can be eliminated.
--
--
function Syncs:coalesce()
   for vcs,list in pairs(self.lists) do
      table.sort(list, function (a,b) return a.sort < b.sort end)
      local n = 1
      while n < #list  do
         local a,b = list[n], list[n+1]
         if beginsWith(b.sort, a.sort) then
            -- a overlaps b
            if a.ver ~= b.ver and b.ver ~= 'have' then
               errorf("pm: version conflict between %s://%s%s@%s and %s@%s",
                      vcs.scheme, vcs.host, a.path, tostring(a.ver),
                      b.path, tostring(b.ver))
            elseif a.tail == "" or a.tail == b.tail then
               -- a includes everything in b  => discard b
               -- (This is just for efficiency; we do not detect all such cases.)
               remove(list, n+1)
               n = n - 1
            end
         end
         n = n + 1
      end
   end
end


function Syncs:retrieve()
   for vcs, list in pairs(self.lists) do
      for _,sync in ipairs(list) do
         vcs:sync( sync.path, sync.ver )
      end
   end
end

function Syncs:show()
   for vcs, list in pairs(self.lists) do
      for _,sync in ipairs(list) do
         vcs:show(sync.path, sync.ver)
      end
   end
end


----------------------------------------------------------------
-- PM : Package Manager class
----------------------------------------------------------------

local PM = Object:new()

function PM:initialize(cfg, os)
   os = os or Sys:new(cfg)

   self.cfg = cfg
   self.os = os
   self.pkgs = {}
   self.pkgsByURI = {}
   self.syncs = Syncs:new()
   self.countRoots = 0
   self.rootNames = {}
   self.depth = 0
   self.sharedTables = memoize.newTable(function() return {} end)

   -- vcs: scheme -> VCS instance
   self.vcs = cfg.handlers or {
      p4 = P4VCS:new(cfg, os),
      file = FileVCS:new(cfg, os),
   }
end


function PM:runHooks(name, arg)
   if arg == nil then
      arg = self
   end
   for _,hook in ipairs(self.cfg.hooks[name] or {}) do
      hook.fn(arg)
   end
end


-- Retrieve file contents:  ReadFile(uri) -> data, path
--    data = contents of file
--    path = local FS path to file (if writable file or "file:")
--
function PM:readFile(uri)
   local session, tu = self:examineURI(uri)
   return session:readFile(tu.path, tu.version)
end


function PM:examineURI(uri)
   local t = pmuri.parse(uri)
   if not t.scheme then
      error("pm: bad package URI: " .. uri)
   end
   local vcs = self.vcs[t.scheme]
   if not vcs then
      error("*: unknown URI scheme: " .. tostring(t.scheme))
   end
   local session = vcs:getSession(t.scheme, t.host, t.path)
   return session, t --path, t.version, t.params
end


function PM:checkDepth(root)
   -- count distinct files
   if not self.rootNames[root] then
      self.rootNames[root] = true
      self.countRoots = self.countRoots + 1
   end

   -- In order to avoid infinite recursion in parametrized packaged, place a
   -- limit on dependency chain lengths.  We count actual root directories
   -- so this limit constrains nesting of parametrized versions, but does
   -- not generally constrain the size of the package tree.  10-deep nesting
   -- in each package seems ridiculously large.
   if self.depth > self.countRoots*10 then
      errorf("pm: apparent infinite recursion; dependency depth = %d", self.depth)
   end
end


-- Find/construct a package object for a URI without creating duplicate
-- packages for equivalent URIs.
--
function PM:getPackage(uriRel, uriBase, parent)
   local uri = pmuri.gen(uriRel, uriBase)
   local session, tu = self:examineURI(uri)
   local path = tu.path
   local notFounds = ""

   local function newLoc(suffix)
      tu.path = suffix and catFile(path, suffix) or path
      return pmuri.gen(tu)
   end

   self.depth = self.depth + 1

   -- If we have previously constructed a package with one of the possible
   -- canonical names, we can skip the auto-detection steps.

   tu.scheme, tu.host = session.scheme, session.host
   uri = newLoc()
   local cache = self.pkgsByURI
   local p = cache[uri] or cache[newLoc"pak"]
   if p == false or p==nil and path:sub(-1)=="/" then
      p = cache[newLoc"..."]
   end
   if p then
      self.depth = self.depth - 1
      return p
   end

   -- Find canonical name of package, either:
   --   a) <path> if it has no trailing slash and is a file
   --   b) <path>/pak it that is a file
   --   a) <path>/..., if <path> identifies a directory

   local pak, pakfile
   if path:sub(-4) ~= "/..." then
      if path:sub(-1) ~= "/" then
         pak, pakfile = session:readFile(path, tu.version)
      end
      if not pak then
         notFounds = notFounds .. "\n        File: " .. path
         local path_pak = catFile(path, "pak")
         pak, pakfile = session:readFile(path_pak, tu.version)
         if pak then
            path = path_pak
         else
            notFounds = notFounds .. "\n        File: " .. path_pak
            cache[newLoc"pak"] = false
            path = catFile(path, "...")
         end
      end
   end

   if path:sub(-4) == "/..." then
      if not session:dirExists( path:sub(1,-4), tu.version) then
         notFounds = notFounds .. "\n   Directory: " .. path:sub(1,-4)
         errorf("pm: Invalid location: %s\nNot a file or directory; " ..
                   "none of the following exist%s:%s\n",
                uri,
                (tu.version and " as of version " .. tu.version or ""),
                notFounds)
      end
   end

   uri = newLoc()
   p = Package:new(uri, self.os, parent, self)
   cache[uri] = p
   insert(self.pkgs, p)

   self:checkDepth(p.root)

   p.children = {}
   for dname, duri in pairs(p.deps) do
      p.children[dname] = self:getPackage(duri, p.root, p)
   end

   self.depth = self.depth - 1
   return p
end


-- Find all root directories that are underneath another root
--
local function findNestedRoots(pkgs)
   local t = {}
   for _,p in ipairs(pkgs) do
      -- construct root without version & parms (and with trailing "/")
      local u = pmuri.parse(p.root)
      local root = pmuri.gen{ scheme=u.scheme, host=u.host, path=u.path}
      insert(t, {pkg=p, root=root})
   end
   local function byRoot(a,b)
      return a.root < b.root
   end
   table.sort(t, byRoot)

   local nests = {}
   local prev = t[1]
   for n = 2, #t do
      if beginsWith(t[n].root, prev.root) and #t[n].root > #prev.root then
         insert(nests, { top = prev.pkg, btm = t[n].pkg })
      else
         prev = t[n]
      end
   end
   return nests
end


-- Find a dependency cycle in the graph.  Returns an array describing the
-- cycle, starting at the top.  Returns nil if there is no cycle.
-- The returned array contains one table per node in the cycle, with:
--    node      = node
--    childName = name for child (next element in the cycle array)
--
local function findCycle(top)
   local childof = {}
   local names = {}
   local function visit(node)
      if childof[node] then
         -- detected loop
         local t = {}
         local parent = node
         repeat
            local child = childof[parent]
            insert(t, {node=parent, childName=names[child]})
            parent = child
         until child == node
         return t
      end
      for childName,child in pairs(node.children) do
         childof[node] = child
         names[child] = childName
         local cycle = visit(child)
         if cycle then return cycle end
      end
      childof[node] = false
   end
   return visit(top)
end


-- Retrieve a package description and any descendants, recursively.
--
function PM:visit(uri)

   -- 'uri' is as specified on the command line.  This may be a URI, a
   -- Perforce path (relative to the current P4 client), or a local file
   -- name, absolute or relative.  If no scheme is provided, or if it begins
   -- with a single letter and a colon, we treat it as a file.

   if uri:match("^//") then
      -- "//path" or "///path"  -->  "p4:///path"
      uri = uri:gsub("^///?", "p4:///")
   end

   local tu = pmuri.parse(uri)
   if not tu.scheme or tu.scheme:match("^[a-zA-Z]$") then
      -- It's a file name: find its absolute URI, using "p4:" it is mapped
      -- to/from a Perforce location; otherwise use "file:"
      local file = tu.path == "" and "." or tu.path
      local p4session = self:examineURI("p4:")
      local tw = p4session:where(file)
      if not tw then
         tw = File:where(file)
      end
      tw.params, tw.version = tu.params, tu.version
      uri = pmuri.gen(tw)
   end

   -- Visit package (and recursively its dependencies)
   local top = self:getPackage(uri)

   -- look for cycles
   local cycle = findCycle(top)
   if cycle then
      local t = {}
      for k,v in ipairs(cycle) do
         insert(t, string.format("      %s in %s", v.childName, v.node.uri))
      end
      errMsg("depsCycle", { chain=concat(t,"\n") }, self.os)
   end

   -- Check for nested roots
   local nestPkgs = findNestedRoots(self.pkgs)
   for _,w in ipairs(nestPkgs) do
      errMsg("nestedPkg", w, self.os)
   end

   -- Collect all paths to be synced
   for _,p in ipairs(self.pkgs) do

      -- Pin 'sync' down to a specific version when none is specified
      local session, tu = self:examineURI(p.root)
      p.version = session:fixVersion(tu.version)

      for _,f in ipairs(p.files) do
         self.syncs:add(session, p4Encode(p.rootPath) .. "/" .. f, p.version)
      end
   end

   -- Coalesce redundant syncs & check for version conflicts
   self.syncs:coalesce()

   self:runHooks("onVisit")
   return top
end


-- Sort packages so that children precede their parents
--
local function childSort(pkgs)
   local list = {}
   local visited = {}

   local function v(node)
      if visited[node] then return end
      visited[node] = true
      if node.children then
         for _,c in pairs(node.children) do v(c) end
      end
      insert(list, node)
   end
   for _,p in ipairs(pkgs) do
      v(p)
   end
   return list
end


-- Map package and its dependencies into local workspace
--
function PM:map(uri)
   local top = self:visit(uri)
   local sessionlist = {}

   local pkgsByPath = (map.i"v")(self.pkgs)
   table.sort(pkgsByPath, function (a,b) return #a.rootPath < #b.rootPath end)

   -- Find/map each package root in local workspace
   for _,p in ipairs(pkgsByPath) do
      local function mapFunc()
         local mapping = p:getMapping() or self.cfg.mapping or pmlib.mapLong
         return mapping(p)
      end
      local session, tu = self:examineURI(p.root)
      p.fsRoot = session:createMap(tu.path, mapFunc)
      insert(sessionlist, session)
   end

   -- Expand strings & evaluate functions that may depend upon child
   -- packages, processing children before parents.
   for _,p in ipairs( childSort(self.pkgs) ) do
      p:expandFields()
      p.fsResult = fu.resolve(p.fsRoot, p.expanded.result)
   end

   -- Update each workspace
   for _,session in ipairs(sessionlist) do
      session:applyMaps()
   end

   self:runHooks("onMap")
   return top
end

function PM:show(uri)
   self:map(uri)
   return self.syncs:show()
end


local function defaultMessage(top)
   local o = Array:new()
   local ec = top.expanded.commands

   local cdPath = fu.relpathto(xpfs.getcwd(), top.fsRoot)
   if ec.make or ec.maketree then
      local mktree = ""
      o("To build:")
      if cdPath ~= "." then
         o("    cd %s", cdPath)
         mktree = "cd " .. quoteArg(cdPath) .. " && "
      end
      local format = "    %s"
      if ec.maketree then
         o("    %-24s # builds the package and its dependencies", ec.maketree)
         format = "    %-24s # builds just the package"
         top.toMakeTree = mktree .. ec.maketree
      end
      if ec.make then
         o(format, ec.make)
      end
   else
      o("Local path: %s", cdPath)
   end

   return concat(o, "\n")
end


-- Retrieve a package and its dependencies and glue them together
--
function PM:get(uri)
   local top = self:map(uri)

   -- Retrieve the sources
   self.syncs:retrieve()

   -- Generate glue files
   local written = {}
   for _,p in ipairs(self.pkgs) do
      p:genGlue()
      self:runHooks("packageGlue", p)
      p:writeGlue(written)
   end

   -- Write summary
   self.os:printF("Done.  %s package%s retrieved.\n", #self.pkgs, plural(#self.pkgs))

   local message = top.message or defaultMessage
   local text = type(message) == "string" and message or message(top)
   if text then
      self.os:printF("%s\n", text)
   end

   self:runHooks("onGet")
   return top
end


return PM
