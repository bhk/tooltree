local qt = require "qtest"

require("timeharness").install()

local thread = require "thread"
local xpio = require "xpio"
local O = require "observable"
local After = require "after"


local eq = qt.eq


local function test()
   local sub = {
      count = 0,
      invalidate = function (self) self.count = self.count + 1 end
   }

   local tbool = O.Slot:new(false)

   -- When `tbool` is false, a's value is false.

   local a = After:new(tbool, 1)
   a:subscribe(sub)
   eq(false, a:get())

   -- When time changes while `tbool` is false, no invalidations occur and no
   -- timer is set.

   xpio.settime(xpio.gettime() - 1)
   eq(sub.count, 0)
   eq(false, a:get())
   thread.settle()
   eq({0, 0}, {thread.queryState()})

   -- When `tbool` is set to the future, value will still be false, but timer
   -- will be set.

   local tTrue = xpio.gettime() + 1
   tbool:set(tTrue)
   thread.settle()
   eq(sub.count, 1)
   eq(false, a:get())  -- should start timer thread
   thread.settle()     -- should more timer thread to sleepers queue
   eq({1, 0}, {thread.queryState()})

   -- When timer becomes ready, value transitions to tTrue and no timer
   -- should remain.

   xpio.settime(tTrue + 1)
   thread.settle()
   eq(sub.count, 2)
   eq(tTrue, a:get())
   eq({0, 0}, {thread.queryState()})

   a:unsubscribe(sub)
end


thread.dispatch(test)
