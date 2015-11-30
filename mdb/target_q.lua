-- target_q.lua
--
-- Exercise target.lua and mdbagent.lua

local qt = require "qtest"
local fsu = require "fsu"
local observable = require "observable"
local thread = require "thread"
local Target = require "target"
local farf = require "farf"
-- @require mdbagent   -- indirect dependency

-- require("trace").on()


local eq = qt.eq

local luaExe = os.getenv("LUA")
local outdir = assert(os.getenv("OUTDIR"), "OUTDIR not defined")

local function newArray()
   return setmetatable({}, { __index = table })
end


----------------------------------------------------------------
-- Target-related Utilities
--
-- Unlike typical clients of the `target` module, these tests operate in a
-- synchronous, blocking fashion.  The following functions provide a
-- synchronous interface.
--
----------------------------------------------------------------

local target
local filename
local breakpoints
local stack
local current
local log


-- Wait for the target process to complete execution and processing previous
-- requests.
--
local function wait(waitFor)
   waitFor = waitFor or "pause"

   local status, busy
   for tries = 1, 50 do
      status = target.status:get()
      busy = target.busy:get()
      if not busy and status == waitFor then
         -- set `current` to the top stack frame
         local s = stack and stack:get()
         current = s and s[1]
         if farf("p") then
            local i = debug.getinfo(2, "Sl")
            qt.printf("%s:%s: wait -> %s\n", i.short_src, i.currentline, status)
         end

         local lval = target.log:get()
         log = {}
         for n = 1, lval.len do
            log[n] = lval.a[n]
         end
         return
      end
      if status == "exit" then break end
      thread.sleep(tries/500)
   end

   -- fail and display value
   eq(waitFor, status .. (busy and "(busy)" or ""))
end


local function clearLog()
   target.log:set{ a={}, len=0 }
end


local testSubscriber = {
   invalidate = function () end
}


local function watchStack()
   stack = target:observe("stack")
   stack:subscribe(testSubscriber)
end


local function observeOnce(name)
   local ob = target:observe(name)
   ob:subscribe(testSubscriber)
   wait()
   local result = ob:get()
   ob:unsubscribe(testSubscriber)
   return result
end


local function getVars(level)
   local a = observeOnce("vars/" .. level)
   -- translate { {name=X, value=Y}, ...}  to {X=Y, ...}
   local t = {}
   for _, rec in ipairs(a) do
      t[rec.name] = rec.value
   end
   return t
end


local function getPairs(desc)
   return observeOnce("pairs/" .. desc)
end


-- Create a target from an embedded Lua source snippet
--
local function createTarget(source, loadTarget)
   breakpoints = observable.Slot:new({})
   stack = nil
   current = nil

   filename = (outdir .. "/target_q_tmp.lua"):gsub("//", "/")
   fsu.nix.write(filename, source)

   local cmd = newArray()
   for word in luaExe:gmatch("%S+") do
      cmd:insert(word)
   end
   if loadTarget then
      cmd:insert("mdbagent.lua")
   else
      cmd:insert("-l")
      cmd:insert("mdbagent")
   end
   cmd:insert(filename)

   farf("p", "-- new target --")
   target = Target:new(cmd, breakpoints)

   wait()
end


local function showStack()
   local stk = stack:get()
   qt.printf("Stack:\n")
   for n = 1, #stk do
      local f = stk[n]
      qt.printf("  %s:%s: %s [%s]\n", f.file, f.line, f.name, f.what)
   end
end


----------------------------------------------------------------
-- basic tests

local sourceBasic = [[
local a = 1
]]


local function testBasic()
   createTarget(sourceBasic)

   -- Target immediately pauses at first line of execution

   eq(target.status:get(), "pause")

   watchStack()
   wait()
   eq(1, current.line)
   eq(filename, current.file)

   target:run()
   wait("exit")

   target:close()
end


----------------------------------------------------------------
-- target:eval()


local sourceEval = [[
local uu = 7
local function ff(aa)
  local ll = aa * uu
  local tt = { "a", x=1 }
  return ll
end
ff(2)
]]


-- Perform eval and return an array of result values
--
local function eval(command)
   wait()
   clearLog()
   eq(target:eval(command), nil)
   wait()

   local logval = target.log:get()
   local a = logval.a
   local len = logval.len

   -- command should be echoed first

   eq(a[1], "C" .. command)

   -- an error should result in one "E" record
   if tostring(a[2]):match("^E") then
      eq(#a, 2)
      return {nil, a[2]:sub(2)}
   end

   -- success results in zero or more "R" records
   local results = newArray()
   for n = 2, len do
      eq(a[n]:sub(1,1), "R")
      results:insert(a[n]:sub(2))
   end
   return results
end



local function testEval()
   createTarget(sourceEval)
   watchStack()
   wait()
   eq(current.line, 1)

   target:run("over")
   wait()
   eq(current.line, 6)

   target:run("over")
   wait()
   eq(current.line, 7)

   target:run("in")
   wait()
   eq(current.line, 3)

   wait()
   eq(3, current.line)
   eq("ff", current.name)

   -- inspect variables
   local v = getVars(1)
   eq(v, { aa="2", uu="7" })

   -- simple eval
   local out = eval("1+1, 3")
   eq(out, {"2", "3"})

   -- eval error case
   out = eval("function")
   eq(out[1], nil)
   eq("string", type(out[2]))

   -- read local variable
   out = eval("aa")
   eq(out, {"2"})

   -- read upvalue
   out = eval("uu")
   eq(out, {"7"})

   -- read global
   out = eval("math.pi")
   eq(out, {tostring(math.pi)})

   -- modify upvalue & local, and ensure the new values are visible both to
   -- the target code and the evaluated command
   out = eval("uu = 4; return uu")
   eq(out, { "4" })

   out = eval("aa = 3; return aa")
   eq(out, { "3" })

   -- debug.log
   clearLog()
   target:eval("debug.log(12) or 1")
   wait()
   eq(log, { "Cdebug.log(12) or 1", "V12", "R1" })

   -- debug.printf
   clearLog()
   target:eval("debug.printf('%s %s', 1, 2)")
   wait()
   eq(log[2], "P1 2")

   target:run("over")
   v = getVars(1)
   eq(v.ll, "12")

   -- value descriptions
   out = eval([[uu = 'a"b\010']])
   eq(out, {})
   v = getVars(1)
   eq(v.uu, [["a\"b\n"]])

   -- tables
   target:run("over")
   v = getVars(1)
   eq(v.tt, "table 1")

   local p = assert(getPairs("table 1"))
   eq(p, { {'"x"', '1'}, {'1', '"a"'} })

   -- go
   target:run()
   wait("exit")

   target:close()
end


----------------------------------------------------------------
-- breakpoints
-- debug.pause()
-- debug.printf()


local sourceDebug = [[
for n = 1, 2 do
   g = n
end
debug.pause()
debug.printf("hi")
error("yow")
debug.printf("there")
]]


local function testDebug()
   createTarget(sourceDebug, true)
   watchStack()
   clearLog()

   -- trap on breakpoints
   breakpoints:set{ [filename] = {2} }
   target:run()
   wait()
   eq(2, current.line)

   -- same breakpoint, second time
   target:run()
   wait()
   eq(2, current.line)

   -- debug.pause
   target:run()
   wait()
   eq(4, current.line)

   target:run("over")
   wait()
   eq(5, current.line)
   eq({}, log)

   -- trap on error: should pause in ERROR_HANDLER
   target:run()
   wait()
   eq({"Phi"}, log)
   eq(current.file, nil)
   eq(current.name, "UNCAUGHT ERROR")

   target:close()
end


----------------------------------------------------------------
-- debug into coroutines


local sourceCoro = [[
local function f1(a, b)
  debug.printf(a .. b)
end
local c1 = coroutine.create(f1)
coroutine.resume(c1, "f", "1")
c1 = nil

local function f2()
  debug.printf("f2")
end
local c2 = coroutine.create(f2)
coroutine.resume(c2)
c1 = true

local function fail() return (nil)() end
local succ, err = coroutine.resume(coroutine.create(fail))
if succ == false and string.match(err, "^[^ ]+ attempt to call a nil value$") then
   debug.printf("ok")
else
   debug.printf("fail: %s, %s", succ, err)
end
]]


local function testCoro()
   createTarget(sourceCoro, true)
   watchStack()
   clearLog()

   -- trap on breakpoints
   breakpoints:set{ [filename] = {5, 12} }
   wait()

   target:run()
   wait()
   eq(5, current.line)

   -- step "in" enters coroutine

   -- `coroutine.resume` wrapper should be invisible, but the error handler
   -- wrapping the coroutine function itself *is* visible.
   target:run("in")
   wait()

   target:run("in")
   wait()
   eq(2, current.line)
   eq({}, log)

   -- coroutine.resume forwards arguments

   target:run("over")
   wait()
   eq(3, current.line)
   eq(log, {"Pf1"})

   -- run to next resume
   target:run()
   wait()
   eq(12, current.line)

   -- step over coroutine resume
   target:run("over")
   wait()

   eq(13, current.line)

   -- Assertion: error values are reported as when not in the debugger
   clearLog()
   target:run()
   wait()
   eq(stack:get()[2].line, 15)  -- stopped at error
   target:run()
   wait("exit")
   eq(log, { "Pok" })

   target:close()
end


----------------------------------------------------------------
-- error trapping


-- Assertions:
--
--  * pcall() and xpcall() forward all arguments & return values
--
--  * xpcall() and pcall() error messages are as expected
--
--  * execution will be halted at error on line 2, even when
--    within pcall and xpcall
--

local sourceErr = [[
local function err1(...)
   return (nil)[1]
end

local function succ1(...)
   return select("#", ...), ...
end

local ok, a, b, c = pcall(succ1, 9, 8)
assert(ok == true)
assert(a == 2)
assert(b == 9)
assert(c == 8)
debug.printf("a")

local ok, err = pcall(err1)
assert(ok == false)
assert(err:match("^.-tmp.lua:2: attempt to index a nil value"))
debug.printf("b")

local ok, err = xpcall(err1, function (e) return ">" .. e end)
assert(ok == false)
assert(err:match("^>.-tmp.lua:2: attempt to index a nil value"))

debug.printf("done")
debug.pause()
]]


local function testErr()
   createTarget(sourceErr, true)
   clearLog()
   watchStack()

   -- Execution should stop at the first error: in `err1` within `pcall`

   wait()
   target:run()
   wait()
   eq(stack:get()[2].line, 2)
   eq(log, {"Pa"})

   -- run to second error

   target:run()
   wait()

   eq(stack:get()[2].line, 2)
   eq(log, {"Pa", "Pb"})

   -- run to debug.pause

   target:run()
   wait()
   eq(log, {"Pa", "Pb", "Pdone"})

   target:close()
end


----------------------------------------------------------------
-- target:observe()


local sourceObserve = [[
local function f(n)
   if n < 5 then
      n = n + 1
      debug.pause()
      return f(n)
   end
   return n
end

f(0)
]]


local function testObserve()
   createTarget(sourceObserve, true)

   -- When created, stack is not subscribed

   local stack = target:observe("stack")
   eq(stack:isSubscribed(), false)
   eq(nil, stack:get())

   -- A second call to `observe` returns the same value.

   local stack2 = target:observe("stack")
   eq(stack, stack2)
   stack2 = nil

   -- While not subscribed, stack value is not updated.

   target:run()
   wait()
   eq("pause", target.status:get())
   eq(stack:get(), nil)

   -- While subscribed, stack value IS updated.

   stack:subscribe(testSubscriber)
   eq(stack:isSubscribed(), true)

   for n = 1, 10 do
      if stack:get() ~= nil then break end
      thread.sleep(n/100)
   end
   local s = stack:get()
   assert(s ~= nil)
   eq(s[1].line, 4)
   eq(s[1].file, filename)
   eq(s[1].what, "Lua")

   -- When unsubscribed again, values are no longer updated.

   stack:unsubscribe(testSubscriber)
   target:run()
   wait()
   eq(s, stack:get())

   -- TargetValues are weakly held by the Target.

   collectgarbage()
   eq(target.ovalues["stack"], stack)

   stack = nil
   collectgarbage()
   eq(target.ovalues["stack"], nil)

   target:close()
end


----------------------------------------------------------------
-- Interruption


local sourceIntr = [[
while not a do end
debug.printf("done")
while not b do end
]]


local function testIntr()
   createTarget(sourceIntr, true)
   clearLog()
   watchStack()

   -- `pause` can be sent while target is running

   target:run()
   wait("run")
   target:pause()
   wait()

   target:eval("a = true")
   target:run()
   wait("run")
   eq(log, { "Ca = true",
             "Pdone" })

   -- breakpoints can be changed while target is running

   breakpoints:set{ [filename] = {3} }
   wait()
   eq(current.line, 3)

   target:close()
end


----------------------------------------------------------------
-- Performance


local sourcePerf = [[
local xpio = require "xpio"

local function fib(n)
   local r
   if n <= 1 then
      r = n
   else
      r = fib(n-1) + fib(n-2)
   end
   --require("json").decode([=[ [1,3,{"a":4},"asdf",true,false] ]=])
   return r
end

local t0 = xpio.gettime()
fib(23)
local t = xpio.gettime() - t0

local T = t
return t
]]


local function testPerf()
   local fnNormal = load(sourcePerf)
   local tNormal = fnNormal()

   print("   Normal:", tNormal)
   createTarget(sourcePerf, true)
   clearLog()
   watchStack()
   breakpoints:set{ [filename] = {18} }

   target:run()
   wait()

   local tDebugging = tonumber(getVars(1)["t"])
   print("Debugging:", tDebugging)
   print("    Ratio:", tDebugging / tNormal)

   target:close()
end


--------------------------------
-- main
--------------------------------

local done = false

local function main()
   if (os.getenv("DOBENCH") or "") ~= "" then
      testPerf()
      os.exit(1)
   end

   testBasic()
   testEval()
   testDebug()
   testCoro()
   testErr()
   testIntr()
   testObserve()
   done = true
end

thread.dispatch(main)
assert(done)
