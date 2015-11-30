-- simp4 : p4 client simulator
--
-- Simp4 mimics the tiny subset of the P4 client functionality that has been
-- used by simp4 clients (pakman, p4x).  This subset is 'documented' in the
-- unit tests in simp4_q.lua.
--
-- Test code writes a file called ".simdat" to describe the repository state
-- that simp4 should reflect.  The test code can read that file afterwards
-- to discover what simp4 commands have been invoked.  See simp4_q.lua for a
-- description of .simdat.
--

local xpfs = require "xpfs"
local F = require "lfsu"
local fsu = require "fsu"
local qt = require "qtest"

------------------------------------------------------------------------
-- utility functions
------------------------------------------------------------------------

local bVerbose = os.getenv("simp4_v")
local function verb(...)
   if bVerbose then io.stderr:write( qt.format(...) ) end
end

local simdat
local s         -- currently selected server: .files, .info
local c         -- currently selected client: .actions, .haves, .client
local dash_s    -- "-s" was provided?

local function forceWrite(path, data)
   xpfs.remove(path)
   F.write(path,data)
end

local function scriptMode(b)
   dash_s = b
end

local function exit(n)
   if simdat then
      F.write(".simdat", "return " .. qt.describe(simdat))
   end
   if dash_s then
      print("exit: "..n)
   end
   os.exit(n)
end

local function put(mode, ...)
   local str = string.format(...)
   if dash_s then
      print(mode..": "..str)
   else
      local f = (mode == "error") and io.stderr or io.stdout
      f:write(str .. "\n")
   end
end

local function errorf(...)
   put("error", "%s", qt.format(...) )
   exit(1)
end

-- quote a string for use in a Lua pattern
local function stringToPattern(str)
   return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

-- convert P4-style patterm to unrooted Lua pattern
local function p4ToLuaPattern(p)
   return stringToPattern(p):gsub("%%%*", "[^/]*"):gsub("%%%.%%%.%%%.", ".*")
end

-- Parse view line.  Returns:  minus, depot, local, extra
--   minus = "-" or ""
--   depot, local = depot and local patterns (without the trailing "...")
--   extra = extraneous text (if present)
local pvlPat
local function parseViewLine(ln)
   if not pvlPat then
      local lpeg = require "lpeg"
      local P = lpeg.P

      -- fl = literal file, fq = quoted file
      local fl = lpeg.C( (1 - P" " - P"...")^0) * P"..."
      local fq = P('"') * lpeg.C( (1 - P('"') - P('...'))^ 0) * P'..."'
      local fpat = fq + fl
      pvlPat = lpeg.C( P"-" + "" ) * fpat * P" " * fpat * (lpeg.C(lpeg.P(1)^1) + P"")
   end
   return pvlPat:match(ln)
end

-- Ways to name files in Perforce:
--   "depot"   //depot/...   repositiory location; LHS of view spec
--   "client"  //client/...  RHS of view spec
--   "local"   /p4/...       local FS; confusingly called 'clientFile' in fstat

-- Map depot path to local and client paths
--
local function dmap(path, client)
   local cpath
   for n, m in ipairs(client.View) do
      local sub, d, c = parseViewLine(m)
      if d and path:sub(1,#d) == d then
         if sub == "-" then
            cpath = false
         else
            cpath = c .. path:sub(#d+1)
         end
      end
   end
   verb("dmap: %Q -> %Q\n", path, cpath)
   if not cpath then
      return false
   end
   return cpath:gsub("//" .. client.Client, client.Root), cpath
end

-- qt.expect("/cwd/y", dmap("//dx/y", { Root="/cwd", Client="C",
--                                    View={ "//dx/... //C/..." }}))

-- Map depot path to local path and client path; returns false if not mapped
local function depotToLocal(path)
   return dmap(path, c.client)
end

-- convert P4 client spec text to table form:  name -> ( string | array of strings )
local function parseClient(str)
   local g = require "lpeg"
   local nl   = g.P"\r"^0 * g.P"\n"
   local rol  = (- nl * 1) ^ 0
   local name = g.C(g.R("AZ","az","09","__")^1)
   local v1   = g.Cg( name * ":\t" * g.C(rol) * nl)
   local vn   = g.Cg( name * ":" * g.Ct( (nl * "\t" * g.C(rol))^0) * nl )
   local pcs  = g.Cf( g.Cc{} * ( v1 + vn + rol*nl )^0,
                      function (t,k,v) t[k] = v ; return t end)
   return pcs:match(str)
end


local function keys(tbl)
   local ks = {}
   for k in pairs(tbl) do
      ks[#ks+1] = k
   end
   return ks
end


local function sort(tbl, fn)
   table.sort(tbl, fn)
   return tbl
end


-- convert table form of client spec to text form (array of lines, actually)
local function genClient(client)
   local t = { insert = table.insert }

   for _, k in ipairs(sort(keys(client))) do
      local v = client[k]
      if type(v) == "string" then
         t:insert( k..":\t"..v )
      else
         t:insert( k..":" )
         for _,a in ipairs(v) do
            t:insert( "\t"..a )
         end
      end
      t:insert("")
   end
   return t
end

local versionStr = [[
Perforce - The Fast Software Configuration Management System.
Copyright 1995-2007 Perforce Software.  All rights reserved.
Rev. P4/NTX86/2007.2/122958 (2007/05/22).
]]

------------------------------------------------------------------------
-- main
------------------------------------------------------------------------

simdat = loadfile(".simdat")
simdat = simdat and simdat()
if not simdat then errorf("simp4: missing .simdat file!") end
s = simdat
s.log = s.log or {}

-- log command literally
local logstr = table.concat(arg,'|'):gsub(" ", "\\ "):gsub('|', ' ')
table.insert(s.log, logstr)
verb("simp4 command: %s\n", logstr)

local exitCode = 0


-- read '-XXX' options from arg[]
local function readOpts(allowed)
   local opts = {}
   while arg[1] and arg[1]:sub(1,1) == "-" do
      local o = table.remove(arg,1):sub(2)
      if not allowed[o] then errorf("simp4: unknown option '-%s'", o) end
      opts[o] = true
      if allowed[o] == 1 then
         opts[o] = table.remove(arg,1)
      end
   end
   return opts
end

-- check for hook
if s.hook then
   local hookEnv = {
      simdat = s,
      put = put,
      exit = exit,
      scriptMode = scriptMode,
      __index = _G
   }
   local env = setmetatable(hookEnv, hookEnv)
   local fn = assert(load(s.hook, nil, nil, env))
   local rv = fn(...)
end


-- allowed options:
local cmdOpts = {
   print =  {q=0},
   client = {o=0, i=0},
   sync =   {f=0, p=0, n=0},
   fstat =  {Rc=0, Os=0, Ol=0},
   changes = {m=1},
   revert = {a=0}
}

-- read options in the annoying Perforce style
local preOpts, cmd = readOpts{s=0, V=0, p=1, c=1, u=1, P=1}, table.remove(arg,1)
if preOpts.V then
   print(versionStr:gsub("NT", s.os or "NT"))
   exit(0)
end

-- select server
if preOpts.p then
   s = s.ports and s.ports[preOpts.p]
   if not s then
      errorf("simp4: unknown server '%s'", preOpts.p)
   end
end
s.files = s.files or {}

-- select client  (haves[] and actions[] may be client-specific)
c = s
if preOpts.c then
   c = s.clients[preOpts.c]
   if not c then
      errorf("simp4: unknown client '%s'", preOpts.c)
   end
end
c.actions = c.actions or {}
c.haves = c.haves or {}

local postOpts = readOpts( cmdOpts[cmd] or {})
scriptMode(preOpts.s)

local function info1(a)
   for _,str in ipairs(a) do
      print( (dash_s and "info1: " or "... ") .. str )  -- odd but true
   end
   if not dash_s then print() end
end


local function p4Decode(s)
   return ( s:gsub("%%%x%x", function (s) return string.char( tonumber(s:sub(2),16) ) end) )
end

local function where(file)
   if not c.depotCWD then
      -- not under client
      return
   end
   local dp = fsu.nix.resolve(c.depotCWD, file)
   local lp, cp = dmap(dp, c.client)
   return dp, cp, lp
end


-- return files matching pattern in arg[1]
-- assume "//" => depot path, anything else is relative to c.depotCWD
local function matchFiles(set)
   local path, ver = (arg[1] or ""):match("([^@]*)@?(.*)")
   if not path:match("^//") then
      path = (c.depotCWD .. "/" .. path):gsub("/%./", "/")
   end
   local pat = "^("..p4ToLuaPattern(path)..")" .. (cmd=="dirs" and "/" or "$")
   local found = {}
   local sets = { set or s.files, (cmd == "fstat" and c.actions or nil) }
   for _,set in ipairs(sets) do
      for k,v in pairs(set) do
         local m = k:match(pat)
         -- dir matching can generate duplicates, so we skip them here
         -- only fstat is interested in pending adds (v==false)
         if m and not found[m] and (v or cmd=="fstat") then
            found[m] = true
            table.insert(found, m)
         end
      end
   end
   if #found == 0 then
      put("error", "%s - no such file(s).", path)
   end
   table.sort(found)
   return found
end

if cmd == "info" then

   for name,fld in ("name=Client root=Root"):gmatch("(%w+)=(%w+)") do
      put("info", "Client %s: %s", name, c.client[fld])
   end
   for _,v in ipairs(s.info) do
      put("info", "%s", v)
   end

elseif ( cmd == "dirs" or
         cmd == "files" or
         cmd == "fstat" ) then

   for _,file in ipairs( matchFiles() ) do
      if cmd == "fstat" then
         local t = { "depotFile " .. file }
         local cpath = depotToLocal(file)
         if cpath then
            table.insert(t, "clientFile " .. cpath )
            table.insert(t, "isMapped ")  -- note extra space
         end
         if c.haves[file] then
            table.insert(t, "haveRev " .. c.haves[file])
         end
         if c.actions[file] then
            table.insert(t, "action "..c.actions[file])
         end
         if postOpts.Ol then
            table.insert(t, "fileSize "..#(s.files[file] or ""))
         end
         info1(t)
      else
         put("info", "%s", file)
      end
   end

elseif cmd == "print" then

   -- P4 client rev P4/NTX86/2009.1/205670 (2009/06/29) has the following bug:
   --     "p4 -s print ..." does *not* prefix lines with "text: ...".
   -- Not sure how widespread this problem is.

   for _,file in ipairs( matchFiles() ) do
      local x = s.files[file]
      if not postOpts.q then
         put("info", "%s - add change (text)", file)
      end
      for ln in x:gmatch("([^\n]+)\r?\n?") do
         if s.brokenPrintS then
            print(ln)
         else
            put("text", "%s", ln)
         end
      end
   end

elseif cmd == "client" then

   if postOpts.o then
      -- write to stdout
      for _,ln in ipairs( genClient(c.client) ) do
         put("info", "%s", ln)
      end
   elseif postOpts.i then
      -- read client from stdin
      local client = parseClient( io.read("*a") )
      if type(client.View) == "table" then
         for _,map in ipairs(client.View) do
            local m,a,b,extra = parseViewLine(map)
            if not a or extra then
               put("error", "Error in client specification")
               put("error", "Wrong number of words for field 'View'.")
            end
         end
      end
      c.client = client
   else
      errorf("simp4: unsuported 'p4 client' mode: %s", qt.describe(postOpts))
   end

elseif cmd == "sync" then

   local cnt = 0
   for _,file in ipairs( matchFiles() ) do
      local data = s.files[file]
      local lpath = depotToLocal(file)
      if lpath and (postOpts.f or not c.haves[file]) then
         lpath = p4Decode(lpath)
         put("info", "%s - refreshing %s", file, lpath)
         cnt = cnt + 1
         if not postOpts.n then
            if not postOpts.p then
               c.haves[file] = 1
            end
            if F.mkdir_p( (F.splitpath(lpath)) ) then
               forceWrite(lpath, data)
               xpfs.chmod(lpath, "-w")
            else
               cnt = cnt - 1
               put("error", "%s - cannot create parent directory", lpath)
            end
         end
      end
   end
   if cnt == 0 then
      put("error", "%s - file(s) up-to-date.", arg[1])
   end

elseif cmd == "revert" then

   for _,file in ipairs( matchFiles(c.actions) ) do
      local a = c.actions[file]
      local lpath = depotToLocal(file)
      if not lpath then
         put("error", "%s - file(s) not in client view.", file)
      elseif a and not postOpts.a then
         -- do nothing on "revert -a"
         put("info", "%s#%s - was %s, %s",
             file, (a=="add" and "none" or "1"), a,
             (a=="add" and "abandoned" or "reverted"))
         c.actions[file] = nil
         if a == "edit" then
            forceWrite(lpath, s.files[file])
         end
      end
   end

elseif cmd == "where" then

   local dp, cp, lp = where(arg[1])
   if not dp then
      put("error", "%s - must refer to client '%s'.", arg[1], c.client.Client)
      exit(1) -- yes, one
   elseif not lp then
      put("error", "%s - file(s) not in client view.", arg[1])
      exit(0) -- yes, zero
   end
   put("info", "%s %s %s", dp, cp, p4Decode(lp))

elseif cmd == "changes" then

   if arg[1] == "//..." and postOpts.m == "1" then
      put("info", "Change %d on %s by bhk@bhk-mac 'yadda yadda'",
          s.latestChange or 999, s.latestDate or "2010/01/01")
   else
      put("error", "Unsupported options to 'changes' ... only '-m 1 //...' is supported.")
   end

elseif ( cmd == "edit" or
         cmd == "add" or
         cmd == "delete" ) then
   -- just log
elseif cmd then
   errorf("simp4: unknown command: %Q\n", cmd)
else
   errorf("Usage: simp4 <subcommand> [options]")
end

exit(0)
