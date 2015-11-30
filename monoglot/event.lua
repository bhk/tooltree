-- event object

local Object = require "object"
local xpio = require "xpio"

local yield = coroutine.yield

local Event = Object:new()


function Event:wait()
   local task = xpio.getCurrentTask()
   self[#self+1] = task
   yield()
   return task.value
end


function Event:signal(count, value)
   local maxElem = #self
   if not count or count > maxElem then
      count = maxElem
   elseif count <= 0 then
      return 0
   end

   for ndx = 1, maxElem do
      if ndx <= count then
         local task = self[ndx]
         task.value = value
         task:makeReady()
      end
      self[ndx] = self[ndx+count]
   end
   return count
end


return Event
