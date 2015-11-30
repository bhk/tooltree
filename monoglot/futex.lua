-- futex: Lightweight mutex-like abstraction.  Does not require allocation
-- of a lock object ahead of time; any existing object can be used as an ID.

local Event = require "event"


local locks = {}


local function lock(value)
   local held = locks[value]
   if not held then
      locks[value] = true
      return
   end

   if held == true then
      held = Event:new()
      locks[value] = held
   end

   held:wait()
end


local function unlock(value)
   local held = locks[value]
   if held == true or held:signal(1) == 0 then
      locks[value] = nil
   end
end


return {
   lock = lock,
   unlock = unlock
}
