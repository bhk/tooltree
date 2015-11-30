-- agentlib: Implements debug hooks and server-side of MDB protocol

local mdbFD = tonumber(os.getenv("mdbFD"))

------------------------------------------------------------------------
-- Construct insulated environment
--
-- The debugger must be immune to changes made to the global table and other
-- shared tables (math, string, etc.).  We set our environment to a clone of
-- the global table, and clone the top-level tables too.  Alas, the string
-- metamethods are shared, so we must avoid using them -- e.g.  we use
-- `string.match(s, ...)`, not `
--
------------------------------------------------------------------------

local collectgarbage, error, ipairs, load, next, pairs, pcall, print, rawget,
   rawset, select, setmetatable, tonumber, tostring, type, xpcall, _G =
      collectgarbage, error, ipairs, load, next, pairs, pcall, print, rawget,
   rawset, select, setmetatable, tonumber, tostring, type, xpcall, _G

local getmetatable = getmetatable

local function clone(t)
   local new = {}
   for k, v in pairs(t) do
      new[k] = v
   end
   return new
end

local coroutine, debug, io, math, os, string, table =
   clone(coroutine), clone(debug), clone(io), clone(math), clone(os),
   clone(string), clone(table)


local insert, pack, unpack, getinfo =
   table.insert, table.pack, table.unpack, debug.getinfo

local gsub, format, match = string.gsub, string.format, string.match


-- Include other modules, but cover our tracks afterward so that
-- the module being debugged will get its own copies and execute
-- them as it normally would.

local oldLoaded = clone(_G.package.loaded)

-- Reset package.loaded to initial state so that the target program will run
-- as normally.
--
local function reset()
   -- reset (reassigning package.loaded has no effect)
   for k in pairs(package.loaded) do
      _G.package.loaded[k] = oldLoaded[k]
   end
end


local xpio = require "xpio_c"  -- we use minimal xpio functionality
local Object = require "object"
local mdbser = require "mdbser"
local ValueMap = require "valuemap"
local farf = require "farf"


-- Process printf-style format string, calling formatFuncs[C] to process
-- each "%C" sequence.  Returns array of values output by the format
-- funcs. Note: any plain text in `fmt` is formatted using "%s".
--
local function xformat(formatFuncs, fmt, ...)
   local o = {}
   local pos = 1
   local argn = 1

   while pos <= #fmt do
      local esc = "%s"
      local value, p1 = match(fmt, "^([^%%]+)()", pos)

      if not value then
         esc, p1 = match(fmt, "^(%%[^%a%%]*.?)()", pos)
         if esc == "%%" then
            value = "%"
            esc = "%s"
         else
            value = select(argn, ...)
            argn = argn + 1
         end
      end

      local fn = formatFuncs[esc:sub(-1)] or formatFuncs.default
      o[#o+1] = fn(esc, value)
      pos = p1
   end

   return o
end


-- When reporting an error in the debugger code we do not want it to be
-- caught by the target code.  In these cases there is nothing to do but
-- exit the program.

local function fatal(str, level)
   io.stderr:write("ERROR: " .. debug.traceback(str, (level or 1) + 1))
   io.flush(io.stderr)
   os.exit(1)
end

local function assert(...)
   local succ, err = ...
   if not succ then
      fatal(err, 2)
   end
   return ...
end


-- detect global variable accesses
local function gerr(t,k)
   fatal("access to global: " .. k, 2)
end
local _ENV = setmetatable({}, { __index = gerr, __newindex = gerr })


------------------------------------------------------------------------
-- Debug agent
------------------------------------------------------------------------

local gettime = xpio.gettime

local weakKeyMT = { __mode = 'k' }
local function newWeakKeys()
   return setmetatable({}, weakKeyMT)
end


local sock, send, recv, peek
do
   sock = assert(xpio.fdopen(mdbFD))
   local recvBuf = ""

   sock:setsockopt("O_NONBLOCK", true)

   local function blockOn(method, ...)
      sock:setsockopt("O_NONBLOCK", false)
      local a, b = sock[method](sock, ...)
      sock:setsockopt("O_NONBLOCK", true)
      return a, b
   end

   function peek()
      local data, err = sock:try_read(200)
      if data then
         recvBuf = recvBuf .. data
         return true
      end
   end

   -- returns: msgID payload
   function recv(blocking)
      while true do
         local line, rest = match(recvBuf,"(.-)\n(.*)")
         if line then
            recvBuf = rest
            farf("p", "C: %s", line)
            return match(line, "^([^ ]*) ?(.*)")
         end

         if peek() then
            -- have more data
         elseif blocking then
            local data, er = blockOn("try_read", 1000)
            if not data then
               io.stderr:write("mdb: control port closed; exiting\n")
               os.exit(1)
            end
            recvBuf = recvBuf .. data
         else
            return -- not blocking
         end
      end
   end

   function send(mtyp, ...)
      local msg = mtyp .. " " .. mdbser.encode(...)
      farf("p", "S: %s", msg)
      blockOn("try_write", msg .. "\n")
   end

end


-- Value Descriptions: strings of readable utf-8 characters. They may fully
--    describe the value or provide a synopsis.  See mdb.txt.


local MAXSTRINGLEN = 1000

local valueMap = ValueMap:new(100)

local function describeValue(v)
   local tv = type(v)
   if tv == "string" then
      local s = v:sub(1,MAXSTRINGLEN)
      s = gsub(format("%q", s), "\n", "n")
      if #v > MAXSTRINGLEN then
         s = s .. "... " .. valueMap:toID(v)
      end
      return s
   elseif tv == "boolean" or
      tv == "nil" or
      tv == "number" then
      return tostring(v)
   else
      return tv .. " " .. valueMap:toID(v)
   end
end


local valueFormatFuncs = {
   default = function (_, v) return gsub(v, "!", "!0") end,
   Q = function (_, v) return "!2" .. gsub(describeValue(v), "!", "!0") .. "!1" end
}

local function valueFormat(fmt, ...)
   return table.concat(xformat(valueFormatFuncs, fmt, ...))
end


local function valueFromDesc(desc)
   return valueMap:fromID( match(tostring(desc), '(%d+)') )
end


-- getDepth: convert a level to a depth, or vice-versa.  Level and depth are
-- two ways of identifying activation records on the stack.
--
--   "level" counts upwards from the current activation frame (1 = caller
--   of getDepth, 2 = caller of caller of getDepth)
--   "depth" counts down from the top.
--
-- Depth is context-independent, but level is what we need to pass to
-- `getinfo` et al.
--
local prevDepth = 0
local function getDepth(level)
   local d = prevDepth
   local minTop, maxTop
   repeat
      if getinfo(d, 'l') then
         minTop = d
         d = d + 1
      else
         d = d - 1
         maxTop = d
      end
   until minTop == maxTop
   prevDepth = minTop
   return minTop - level
end


----------------------------------------------------------------
-- Local Variables
----------------------------------------------------------------

local LocalVar = Object:new()

function LocalVar:initialize(depth, index, name)
   self.depth = depth
   self.index = index
   self.name = name
end

function LocalVar:get()
   local level = getDepth(self.depth)  -- also converts depth -> level
   local name, value = debug.getlocal(level, self.index)
   return value
end


function LocalVar:set(v)
   local level = getDepth(self.depth)
   return debug.setlocal(level, self.index, v)
end


----------------------------------------------------------------
-- Upvalues
----------------------------------------------------------------

local Upvalue = Object:new()

function Upvalue:initialize(func, index, name)
   self.func = func
   self.index = index
   self.name = name
end


function Upvalue:get()
   local name, value = debug.getupvalue(self.func, self.index)
   return value
end


function Upvalue:set(v)
   return debug.setupvalue(self.func, self.index, v)
end


----------------------------------------------------------------
-- local variable access
----------------------------------------------------------------


-- Return array of variables in scope in the function at `level`
--
local function scanVars(depth)
   local level = getDepth(depth)
   local vars = {}

   if depth < 0 then
      return
   end

   for n = 1, math.huge do
      local name, value = debug.getlocal(level, n)
      if not name then break end
      if not match(name, "%(") then
         insert(vars, LocalVar:new(depth, n, name))
      end
   end

   local func = getinfo(level, "f").func
   for n = 1, math.huge do
      local name, value = debug.getupvalue(func, n)
      if not name then break end
      insert(vars, Upvalue:new(func, n, name))
   end

   return vars
end


-- Return array of {name=..., value=...} records
--
local function getVarValues(depth)
   local vars = scanVars(depth)
   if not vars then
      return
   end

   local t = {}
   for _, var in ipairs(vars) do
      t[#t+1] = { name = var.name, value = describeValue(var:get()) }
   end
   return t
end


-- Return map: varName -> varObjct
--
local function getVarMap(depth)
   local vars = scanVars(depth)
   if not vars then
      return
   end

   local byName = {}
   -- locals might hide upvalues (?)
   for n = #vars, 1, -1 do
      local v = vars[n]
      byName[v.name] = v
   end
   return byName
end


----------------------------------------------------------------
-- Debug hook
----------------------------------------------------------------

-- mode debugger is in
local hookMode = "run"

-- true => stop at next line executed
local hookBreak = true

-- where to stop executing (when returning to hook() from pause mode)
local hookRunLimit = 0

-- hookBP[lnum][source] = true  => break at the file/line
local hookBP = {}

-- stack depth at which target code is paused when hookIdle() is called
local hookDepth

-- subscribed names -> true
local subs = {}

local didEval

-- check for new data after this time
local peekInterval = 0.05
local peekNext = 0


-- Invisible functions: "step in" will not stop when an invisible function
-- is on the call stack.  If they call another function via a tail call, then
-- that other function will be debuggable.

local hookInvisible = newWeakKeys()

local function makeInvisible(...)
   for _, fn in ipairs{...} do
      hookInvisible[fn] = true
   end
end


-- Aliases: when these function appear in a stack frames, their real names and
--   locations will not be returned to the debugger.

local aliases = {}

local function alias(func, name)
   aliases[func] = name
end


local function getStack()
   local level = getDepth(hookDepth)
   local stack = {}
   local frame
   for n = level, 2000 do
      local i = getinfo(n, "nlSf")
      if not i then break end
      if aliases[i.func] then
         frame = {
            name = aliases[i.func],
            what = "D" -- debugger
         }
      else
         frame = {
            line = i.currentline,
            name = i.name,
            file = match(i.source, "^@(.*)"),
            what = i.what
         }
      end
      insert(stack, frame)
   end
   return stack
end


local function getVars(level)
   level = tonumber(level) or 1
   return getVarValues(hookDepth - level + 1)
end


-- Order numbers numerically; put strings before numbers
--
local function cmpPairs(a, b)
   local x, y = a[1], b[1]
   if match(x, '^[%d%-]') and match(y, '^[%d%-]') then
      return tonumber(x) < tonumber(y)
   else
      return x < y
   end
end


local function getPairs(desc)
   local tbl = valueFromDesc(desc)
   if type(tbl) == "table" then
      local p = {}
      for k, v in pairs(tbl) do
         insert(p, {describeValue(k), describeValue(v)})
      end
      table.sort(p, cmpPairs)
      return p
   else
      return { error="stale" }
   end
end


local updateFuncs = {
   stack = getStack,
   pairs = getPairs,
   vars = getVars
}


function updateFuncs.unknown()
   return { error="unk" }
end


-- me -> isValid
--
local sentValues = {}
local sentMode = nil

local function updateValues()
   if hookMode == "pause" then
      local didRun = hookMode == "pause" and sentMode ~= "pause"

      local invalid = {
         stack = didRun,
         pairs = didRun or didEval,
         vars =  didRun or didEval
      }
      didEval = false

      for name in pairs(subs) do
         local funcName, arg = match(name, "([^/]*)/?(.*)")
         if invalid[funcName] or not sentValues[name] then
            local func = updateFuncs[funcName] or updateFuncs.unknown
            local value = func(arg)
            sentValues[name] = true
            send("set", name, value)
         end
      end
   end

   if sentMode ~= hookMode then
      send(hookMode)
      sentMode = hookMode
   end
end


local commands = {}


function commands.bp(bp)
   local lineMap = {}

   for file, lines in pairs(bp) do
      -- translate file name to exactly match `debug.getinfo().source`
      local source = gsub(file, "^[^=]", "@%1")

      for _, line in ipairs(lines) do
         local sourceMap = lineMap[line]
         if not sourceMap then
            sourceMap = {}
            lineMap[line] = sourceMap
         end

         sourceMap[source] = true
      end
   end

   hookBP = lineMap
end


-- mtEvalEnv: metatable for environments for evaluated code

local mtEvalEnv = {}

function mtEvalEnv.__index(env, name)
   local varsByName = rawget(env, 1)
   local var = varsByName[name]
   if var then
      return var:get()
   end
   local globals = varsByName._ENV and varsByName._ENV:get() or _G
   return rawget(globals, name)
end

function mtEvalEnv.__newindex(env, name, value)
   local varsByName = rawget(env, 1)
   local var = varsByName[name]
   if var then
      return var:set(value)
   end
   local globals = varsByName._ENV and varsByName._ENV:get() or _G
   return rawset(globals, name, value)
end


-- Evaluate a command sent from the console
--    cmd = expression or statement
--    varMap = map of varName -> varObject
--
-- Return an array:
--    a[1] = true on success, false => error
--    a[2...] = return values (or error string)
--
function commands.eval(cmd)
   local varMap = getVarMap(hookDepth)

   -- Create environment that exposes locals, upvalues, and globals
   local env = setmetatable({varMap}, mtEvalEnv)

   local r

   send("log", "C" .. cmd)

   -- try to treat it as an expression
   local r = { load("return " .. cmd, "=console", nil, env) }

   if not r[1] then
      -- try to eval as a function body
      local errFirst = tostring(r[2])
      r = { load(cmd, "=console", nil, env) }

      -- prefer first error?
      if not r[1] and (match(errFirst, "<eof>$")
                       or not match(tostring(r[2]), "<eof>$")) then
         r[2] = errFirst
      end
   end

   if r[1] then
      didEval = true
      r = pack( pcall(r[1]) )
   end

   -- Log command and results

   --   require("qtest").printf("eval: %Q -> %Q\n", cmd, r)
   if r[1] then
      for n = 2, r.n do
         send("log", "R" .. describeValue(r[n]))
      end
   else
      send("log", "E" .. tostring(r[2]))
   end
end


function commands.sub(name)
   subs[name] = true
end


function commands.unsub(name)
   subs[name] = nil
   sentValues[name] = nil
end


function commands.pause()
   hookMode = "pause"
end


-- limit = "in" | "out" | "over" | ""
function commands.run(limit)
   if hookMode ~= "pause" then
      -- This is harmless in a UI scenario with multiple windows open, but
      -- tests should not encounter this non-determinisitic case.
      send("log", "Wrun() message dropped.")
   end

   hookMode = "run"
   hookRunLimit = limit or ""
end


-- Read and process commands from the debugger until we are told to
-- continue.  Return number indi
--
local function hookIdle()
   updateValues()

   while true do
      local id, body = recv(hookMode == "pause")
      if not id then
         return
      end

      local fn = commands[id]
      if fn then
         fn(mdbser.decode(body))
      else
         send("log", "Emdb: unknown command: " .. tostring(fn))
      end
      updateValues()
      send("ack")
   end
end

local threadToEnter = newWeakKeys()


local nextID = 1

local function installHook(thread)
   local isMain
   if not thread then
      isMain = true
      thread = coroutine.running()
   end

   local threadID = nextID
   nextID = nextID + 1

   -- stack depth at which target code is paused
   local depth = 0

   -- steop at this depth or less
   local breakDepth = 0

   -- when running, the thread that called resume() to enter this thread
   local threadAbove = nil

   -- coroutine.resume() is called immediately after the call to enter, and
   -- in a tail-call fashion, so it will be at the level of the wrapper
   -- function that calls enter.
   --
   local function enter()
      threadAbove = coroutine.running()
   end

   makeInvisible(enter)

   -- track depth on stack and break on breakpoint or breakDepth
   --
   -- Lua 5.2 behavior: "call" events happen after the stack depth has
   -- increased.  "return" events happen before the stack depth has
   -- decreased.  Oddly, when we get a "tail call" the measured stack depth
   -- has already increased, but on the next event (e.g. line) it will go
   -- back down.  An error trapped by pcall can result in a discontinuity,
   -- in which case the next event we see is "return".
   --
   -- "count" sometimes trigger spurious "line" events (two events for a
   -- single line, where only one event would occur without the count
   -- event).  Count events do not appear to be necessary to break out of a
   -- "while true do end" loop, since the Lua VM sends line events
   -- liberally.

   local function hook(reason, lnum)
      --farf("h", "%s: hook(%s, %s)", threadID, reason, lnum)

      if reason == "line" then
         if hookBreak then
            -- pause here, unless we're stepping into an invisible function
            if hookBreak == true then
               for d = 1, depth do
                  local func = getinfo(1 + d, "f").func
                  if func and hookInvisible[func] then
                     return
                  end
               end
            end
         elseif depth > breakDepth then
            if not (hookBP[lnum] and hookBP[lnum][getinfo(2, "S").source]) then
               if gettime() < peekNext then
                  return
               end
               peekNext = gettime() + peekInterval
               if not peek() then return end
               goto notPaused
            end
         end
         hookMode = "pause"
         ::notPaused::
      else
         -- call, tail call, return
         if reason == "call" then
            depth = depth + 1
         elseif reason == "return" then
            -- subtract 1 because the event after "return" will be lower on the stack
            depth = getDepth(2) - 1
            if depth <= 0 and not threadAbove then
               send("exit")
               debug.sethook()
            end
         end
         return
      end

      -- if our depth estimation is off, we might miss depth-based breaks
      if depth ~= getDepth(2) then
         print("DEPTH", depth, getDepth(2), reason, lnum)
      end
      assert(depth == getDepth(2))
      hookDepth = depth - (tonumber(hookBreak) or 0)

      hookRunLimit = nil

      xpcall(hookIdle, function (msg)
                print(debug.traceback(msg .. " [MDB internal]"))
                os.exit(1)
             end)

      if hookRunLimit then
         -- a `run` command was processed
         hookBreak = hookRunLimit == "in"
         breakDepth = 0
         if hookRunLimit == "over" then
            breakDepth = hookDepth
         elseif hookRunLimit == "out" then
            breakDepth = hookDepth - 1
         end
      end
   end

   if isMain then

      local function mainInitHook(reason)
         farf("h", "mainInitHook %s @ %s", reason, getDepth(2))

         -- tail call shows odd transient bump in stack depth
         depth = getDepth(2) - (reason == "call" and 0 or 1)
         debug.sethook(hook, "clr")
      end

      -- For main thread, start *after* the next call or tail call
      debug.sethook(mainInitHook, "c")
   else
      threadToEnter[thread] = enter
      debug.sethook(thread, hook, "clr")
   end
end



------------------------------------------------------------------------
-- Instrument the target environment
------------------------------------------------------------------------

-- agentCall() enters a coroutine that runs without debug hooks
-- so send() can safely be called.

local function agentMain(fn, ...)
   return agentMain(coroutine.yield(fn(...)))
end

local agentCoro = coroutine.create(agentMain)

local function agentCall(...)
   return assert(coroutine.resume(agentCoro, ...))
end


-- debug.*

local function debugLog(...)
   for n = 1, select('#', ...) do
      agentCall(send, "log", "V" .. describeValue(select(n, ...)))
   end
end


local function debugPrintf(...)
   return agentCall(send, "log", "P" .. valueFormat(...))
end


local function debugPause(level)
   hookBreak = tonumber(level) or 1
end


makeInvisible(debugPrintf,
              debugLog,
              debugPause,
              agentCall,
              assert)


_G.debug.pause = debugPause
_G.debug.log = debugLog
_G.debug.printf = debugPrintf


-- os.exit

local function debugExit(code)
   debugPause(2)
   return os.exit(code)
end

_G.os.exit = debugExit

alias(debugExit, "EXITED")


-- Catch and trap errors


-- `mainHandler` is equivalent to the message handler installed by the Lua
-- interpreter when it runs the "main" package.
local function mainHandler(err)
   debugPause()
   return debug.traceback(err)
end

alias(mainHandler, "UNCAUGHT ERROR")


-- `pcallHandler` is equivalent to the message handler installed by pcall.
--
local function pcallHandler(err)
   debugPause()
   return err
end

alias(pcallHandler, "CAUGHT ERROR")


local function h_xpcall(func, msgh, ...)
   local function xpcallHandler(err)
      debugPause()
      return msgh(err)
   end

   return xpcall(func, xpcallHandler, ...)
end


local function h_pcall(func, ...)
   return xpcall(func, pcallHandler, ...)
end


_G.xpcall = h_xpcall
_G.pcall = h_pcall


-- coroutine.*


local function rethrow(succ, ...)
   if succ then return ... end
   return error(..., 0)
end


local function ico_create(f)
   local function catchError(...)
      return rethrow(xpcall(f, pcallHandler, ...))
   end
   local thread = coroutine.create(catchError)
   installHook(thread)
   return thread
end


local function ico_resume(thread, ...)
   threadToEnter[thread]()
   return coroutine.resume(thread, ...)
end


-- Wrap returns a function that *re-throws* an error after trapping it
-- pcall-style.
--
local function ico_wrap(f)
   local thread = ico_create(f)
   return function (...)
      return rethrow(ico_resume(thread, ...))
   end
end


makeInvisible(ico_wrap, ico_resume, ico_create)

_G.coroutine.create = ico_create
_G.coroutine.wrap = ico_wrap
_G.coroutine.resume = ico_resume


-- xpio tqueue:wait()

local function hookXPIO()
   -- Load the same instance the target program will get.  This should not
   -- noticeably affect the target program.
   local xpio = _G.require "xpio_c"

   local mtQ = getmetatable(xpio.tqueue())
   local _wait = mtQ.wait

   function mtQ:wait(t)
      if not t and self:isEmpty() then
         return nil
      end
      local tStop = xpio.gettime() + (t or math.huge)
      local results = {}
      local dbtask = { _queue = self }

      repeat
         sock:when_read(dbtask)
         local timeout = tStop - xpio.gettime()

         local a = _wait(self, timeout)

         if dbtask._dequeue then
            dbtask:_dequeue()
         end
         for n, task in ipairs(a) do
            if task ~= dbtask then
               results[#results+1] = task
            end
         end
      until #results > 0 or timeout < 0

      return results
   end

   alias(mtQ.wait, "WAITING")
end


--------------------------------
-- exports
--------------------------------


local function start()
   reset()
   hookXPIO()
   return installHook()
end


return {
   start = start,
   mainHandler = mainHandler,

   -- for testing:
   xformat = xformat,
   pcallHandler = pcallHandler
}
