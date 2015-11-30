-- ValueMap:
--
-- A ValueMap associates arbitrary values with short string IDs, from which
-- the original values can be recovered at a later time.  A "retain count"
-- passed to the constructor specifies how many values to keep in memory;
-- otherwise IDs may become invalid when the corresponding value is garbage
-- collected, and strings will accumulate forever.


local Object = require "object"

local ValueMap = Object:new()


function ValueMap:initialize(retainCount)
   self.prevID = 0
   self.map = setmetatable({}, { __mode="v" })
   self.xmap = setmetatable({}, { __mode="k" })

   if retainCount then
      self.retainCount = retainCount
      self.retained = {}
   end
end


function ValueMap:toID(value)
   local n = self.xmap[value]
   if n then
      return tostring(n)
   end

   if value == nil then
      return "0"
   end

   -- obtain next ID number
   n = self.prevID + 1
   self.prevID = n

   -- save value
   self.map[n] = value
   self.xmap[value] = n

   -- retain hard reference & release expired value
   if self.retainCount then
      self.retained[n] = value
      local oldID = n - self.retainCount
      local old = self.retained[oldID]
      self.retained[oldID] = nil
      if type(old) == "string" then
         self.xmap[old] = nil
         self.map[oldID] = nil
      end
   end

   return tostring(n)
end


function ValueMap:fromID(id)
   local n = tonumber(id)
   return n and self.map[n]
end


return ValueMap
