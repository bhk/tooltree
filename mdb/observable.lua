-- Observables

local Object = require "object"


--------------------------------
-- Observable base class
--------------------------------

local Observable = Object:new()


function Observable:initialize()
   self.subscribers = {}
   self.valid = false
end


function Observable:invalidate()
   if self.valid then
      for sub in pairs(self.subscribers) do
         sub:invalidate(self)
      end
      self.valid = false
   end
end


function Observable:subscribe(sub)
   local subs = self.subscribers
   local wasEmpty = not next(subs)
   subs[sub] = (subs[sub] or 0) + 1

   if wasEmpty then
      self:onOff(true)
   end
end


function Observable:unsubscribe(sub)
   local subs = self.subscribers
   local count = subs[sub] or 0
   subs[sub] = count > 1 and count-1 or nil

   if not next(subs) then
      self:onOff(false)
   end
end


function Observable:isSubscribed()
   return next(self.subscribers) ~= nil
end


function Observable:onOff()
   -- nothing to do (in base class)
end


function Observable:hasInstance(obj)
   while type(obj) == "table" do
      if obj == self then
         return true
      end
      obj = getmetatable(obj)
      obj = obj and obj.__index
   end
   return false
end


--------------------------------
-- Slot
--------------------------------


local Slot = Observable:new()


function Slot:initialize(value)
   Observable.initialize(self)
   self.value = value
end


function Slot:set(v)
   if v ~= self.value then
      self.value = v
      self:invalidate()
   end
end


function Slot:get(v)
   if self.valid ~= true then
      if self.valid == nil then
         error("Slot:get() called during invalidation")
      end
      self.valid = true
   end
   return self.value
end


--------------------------------
-- Func
--------------------------------


local Func = Observable:new()


function Func:initialize(fn, ...)
   Observable.initialize(self)
   self.fn = fn
   self.inputs = table.pack(...)
   self.obInputs = {}  -- argn -> observable

   for argn, o in ipairs(self.inputs) do
      if Observable:hasInstance(o) then
         self.obInputs[argn] = o
      end
   end
end


function Func:get()
   if not self.valid then
      local inputs = self.inputs
      for argn, o in pairs(self.obInputs) do
         inputs[argn] = o:get()
      end
      self.valid = true
      self.value = self.fn(table.unpack(inputs, 1, #inputs))
   end
   return self.value
end


function Func:onOff(isOn)
   for _, o in pairs(self.obInputs) do
      if isOn then
         o:subscribe(self)
      else
         o:unsubscribe(self)
      end
   end
   -- we are entering or leaving an un subscribed state, in which we do not
   -- receive invalidations, so our state is not known.
   self.valid = false
end


--------------------------------
-- Log
--------------------------------

-- An observable Log is a "persistent" (versioned) array. While its data
-- model is that of an array, it supports limited operations: `append` and
-- `clear`.  "Modifications" to the log produce new values. Each value is
-- describe by a table:
--
--    { len = <number>, a = <table> }
--
-- where `len` is the number of elements, and `a[1]` holds the first
-- element, and so on.  The "actual" size of the table `a` might be larger
-- than `len` (such elements are to be ignored).


local Log = Slot:basicNew()


function Log:initialize()
   Slot.initialize(self)
   self:clear()
end


function Log:append(item)
   local v = self.value
   local a, len = v.a, v.len+1
   a[len] = item
   self:set{ a=a, len=len }
end


function Log:clear()
   self:set{ a={}, len=0 }
end


return {
   Slot = Slot,
   Func = Func,
   Log = Log,
   Observable = Observable
}
