-- after.lua: time-dependent observable

-- Definition: A "tbool" or "timed boolean" value is one that can hold
-- either `false` or a number.
--
-- An `After` instance is a timed boolean that observes another timed
-- boolean, and reflects its value but only when the value is less than the
-- current time by a "lag" factor.  Its value is `false` otherwise.
--
-- This can serve as a "debouncer" if the lag factor is non-zero and the
-- observed value reports the time of its last transition from false.
--
-- This can also serve as a simple timer, transitioning to true at a given
-- time, when the lag is zero and the observed value is a constant (or a
-- changeable expiration time).
--

local O = require "observable"
local thread = require "thread"
local xpio = require "xpio"

local gettime = xpio.gettime

local After = O.Observable:basicNew()


function After:initialize(when, lag)
   O.Observable.initialize(self)
   self.when = when
   self.lag = lag
end


function After:onOff(isOn)
   if isOn then
      self.when:subscribe(self)
   else
      self.when:unsubscribe(self)
      self:cancelAfter()
   end
end


-- TODO: move this to Observable base class
function After:get(v)
   if self.valid ~= true then
      if self.valid == nil then
         error("Observable:get() called during invalidation")
      end
      self.value = self:calc()
      self.valid = true
   end
   return self.value
end


function After:calc()
   local t = self.when:get()

   if t then
      self.tWait = t + self.lag
      if self.tWait > gettime() then
         self:startTimer()
         t = false
      end
   end

   return t
end


function After:timerFunc()
   while gettime() < self.tWait do
      thread.sleepUntil(self.tWait)
   end
   self:invalidate()
   self.timerThread = nil
end


function After:startTimer()
   if not self.timerThread then
      self.timerThread = thread.new(self.timerFunc, self)
   end
end


function After:cancelAfter()
   if self.timerThread then
      thread.kill(self.timerThread)
      self.timerThread = nil
   end
end


return After
