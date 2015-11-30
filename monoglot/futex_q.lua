local qt = require "qtest"
local thread = require "thread"
local futex = require "futex"


local function writer(obj, str, n)
   futex.lock(obj)

   for n = 1, #str do
      obj.data = obj.data .. str:sub(n,n)
      thread.yield()
   end

   futex.unlock(obj)
end


local function writeMultiple(num)
   local text = "abcd"
   local obj = { data = "" }

   local threads = {}
   for n = 1, num do
      threads[n] = thread.new(writer, obj, text, n)
      thread.yield()
   end

   for n = 1, num do
      thread.join(threads[n])
   end

   qt.eq(obj.data, text:rep(num))
end


local done = false

local function main()
   writeMultiple(1)
   writeMultiple(2)
   writeMultiple(21)

   done = true
end

thread.dispatch(main)
assert(done)
