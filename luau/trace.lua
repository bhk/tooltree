-- Trace execution of Lua code
--
-- Usage:
--
--     require("trace").on{ MODULES... }
--
-- Wishlist:
--  * <MODE> = "l" (show all lines) or "c" (show only call/return)
--  * Automatically discover level of nesting when tracing is intiated in a
--    thread, and enable tracing for functions currently on the stack.
--

local debug = require "debug"
local memoize = require "memoize"
local qt = require "qtest"


-- threadID :: thread -> ID
local prevThreadID = 0
local threadID = memoize.newTable(
   function (thread)
      prevThreadID = prevThreadID + 1
      return prevThreadID
   end)


-- log
local prevThread = coroutine.running()
local function log(str)
   if prevThread ~= coroutine.running() then
      print("--------[thread " .. threadID[coroutine.running()] .. "]--------")
      prevThread = coroutine.running()
   end
   print(str)
end


local function fileLine(i)
   return i.short_src .. ":" .. i.currentline .. ":"
end


local indent = memoize.newTable(
   function (level)
      return string.rep("  ", level)
   end
)


-- debug hook, when tracing
local traceHook = nil


local function start(spec, level)
   local thread = coroutine.running()
   spec = spec or {}

   -- inspect calling context
   local i = debug.getinfo(thread, level, 'nlS')
   if i then
      log(indent(level) .. fileLine(i) .. " Tracing ON..." )
   end

   -- default = trace only if caller's source file
   if not spec[1] then
      spec[1] = i.short_src
      log("Tracing lines in " .. i.short_src)
   end

   local matchSrc = memoize.newTable(
      function (src)
         for _, pat in ipairs(spec) do
            if src==pat or src:match(pat) then
               return true
            end
         end
         return false
      end)

   local function match(i)
      return matchSrc(i.short_src)
   end

   local function fmt(i)
      return i.short_src .. ":" .. i.linedefined .. ": " .. (i.name or "?")
   end


   local function myhook(event)
      if event == "call" then

         level = level + 1

      elseif event == "tail call" then

      elseif event == "line" then

         local i = debug.getinfo(2, 'nSl')
         if match(i) then
            log(indent[level] .. fileLine(i) .. " " .. (i.name or ""))
         end

      elseif event == "return" then

         level = level - 1

      end
   end

   traceHook = myhook

   for thread, _ in pairs(threadID) do
      debug.sethook(thread, myhook, "crl")
   end
end


local _create = coroutine.create
function coroutine.create(...)
   local thread = _create(...)
   if traceHook then
      debug.sethook(thread, traceHook, "crl")
   end
   return thread
end


-- `match` is a function that inspects the file and name of the function
--    to determine whether it should be shown in the trace.
--
local function on(spec)
   return start(spec, 2)
end


local function off()
   local i = debug.getinfo(2, 'nlS')
   print(i.short_src .. ":" .. i.currentline .. ": Tracing OFF.")
   debug.sethook()
end


print("TRACE LOADED in thread " .. threadID[coroutine.running()])
return {
   on = on,
   off = off
}
