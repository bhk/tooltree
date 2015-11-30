local Object = require "object"


----------------------------------------------------------------
-- SubStream
----------------------------------------------------------------

local SubStream = Object:new()


--  parent = stream from which to read
--  readAhead = data already consumed from the parent stream
--  limit = length of th substream

function SubStream:initialize(parent, readAhead, limit)
   self.readAhead = readAhead or ""
   self.parent = parent
   self.limit = limit
end


function SubStream:read(amt)
   if amt <= 0 then
      assert(amt == 0)
      -- read(0) always returns "" (see xpio.c)
      return ""
   elseif amt > self.limit then
      amt = self.limit
      if amt == 0 then
         -- end of stream
         return nil
      end
   end

   local data, err
   local ra = self.readAhead
   if ra ~= "" then
      self.readAhead = ra:sub(amt+1)
      data = ra:sub(1, amt)
   else
      data, err = self.parent:read(amt)
   end

   if data then
      self.limit = self.limit - #data
      return data
   end
   return nil, err
end


-- Consume the remainder of this substream from the parent stream.
--    nil          : end of stream (stream has been "drained")
--    <error>      : error was encountered reading from parent.
--
function SubStream:drain()
   repeat
      local data, err = self:read(4096)
      if data == nil then
         return err
      end
   until false
end


-- extract any remaining read-ahead data
function SubStream:leftovers()
   return self.readAhead:sub(self.limit+1)
end


function SubStream:readable(task)
   if self.readAhead ~= "" or self.limit == 0 then
      return task:ready()
   end
   return self.parent:readable(task)
end


-- Release reference to parent.
function SubStream:close(task)
   self.limit = 0
   self.parent = nil
end


return SubStream
