local qt = require "qtest"
local thread = require "thread"
local Event = require "event"

local outs = ""
local done = false
local eq = qt.eq
local yield = thread.yield

local function waitTwice(evt, name)
   evt:wait()
   outs = outs .. name
   evt:wait()
   outs = outs .. name
end


local function main()
   local e1 = Event:new()

   thread.new(waitTwice, e1, 1)
   thread.new(waitTwice, e1, 2)
   yield()
   eq(outs, "")

   e1:signal()
   yield()
   eq(outs, "12")

   thread.new(waitTwice, e1, 3)
   yield()
   e1:signal()
   yield()
   eq(outs, "12123")
   e1:signal()
   yield()
   eq(outs, "121233")

   -- count and value

   local e2 = Event:new()
   local o2 = ""

   thread.new(function () local v = e2:wait(); o2 = o2..v.."A." end).name = 'A'
   thread.new(function () local v = e2:wait(); o2 = o2..v.."B." end).name = 'B'
   thread.new(function () local v = e2:wait(); o2 = o2..v.."C." end).name = 'C'
   yield()
   yield()
   yield()

   -- signal() returns number of awakened threads
   eq(1, e2:signal(1, "foo"))
   yield()
   yield()
   yield()
   eq(o2, "fooA.")

   o2 = ""
   eq(2, e2:signal(nil, "bar"))
   yield()
   yield()
   yield()
   eq(o2, "barB.barC.")

   done = true
end

thread.dispatch(main)
assert(done)
