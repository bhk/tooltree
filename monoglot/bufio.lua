-- BufIO: read-buffered IO object (file/socket)
--
-- BufIO:read() supports the following formats:
--   <number>       : read up to <number> bytes
--   '=', <number>  : read exactly <number> bytes
--   '*l'           : read one line
--   '*L'           : read one line (include terminator in result)
--   '*a'           : rest rest of stream
--
-- Note: read operations are constrained by LINEMAX and ALLMAX

local Object = require "object"

local concat, insert = table.concat, table.insert

local BufIO = Object:new()


-- amount of data to buffer, typically
BufIO.BUFSIZE = 16384

-- maximum line length to read (including line terminator)
BufIO.LINEMAX = math.huge

-- maximum amount to read via '*a'
BufIO.ALLMAX = 10 * 1000 * 1000


function BufIO:initialize(f)
   self.f = f
   self.buf = ""
end


-- Read up to `amount` bytes
--
local function readN(self, amount)
   if amount <= 0 then
      return ""
   end

   local bytes = self.buf
   local err

   while bytes == "" do
      bytes, err = self.f:read(self.BUFSIZE)
      if not bytes then
         return nil, err
      end
   end

   self.buf = bytes:sub(amount + 1)
   return bytes:sub(1, amount)
end


-- Read exactly `amount` bytes, or up to error/eof.
--
local function readAll(self, amount)
   local size = 0
   local all = {}

   while amount > size do
      local data, err = readN(self, amount - size)
      if not data then
         if size == 0 then
            return nil, err
         end
         break
      end
      insert(all, data)
      size = size + #data
   end

   return concat(all)
end


local function readLine(self, retainEnd)
   local buf = self.buf

   while true do
      local a, b = buf:find("\r?\n")
      if a then
         self.buf = buf:sub(b+1)
         return buf:sub(1, retainEnd and b or a-1)
      end

      local more = self.LINEMAX - #buf
      if more <= 0 then
         return nil, "maximum line length exceeded"
      elseif more > self.BUFSIZE then
         more = self.BUFSIZE
      end

      local data, err = self.f:read(more)
      if not data then
         self.buf = buf
         return nil, err
      end

      buf = buf .. data
   end
end


function BufIO:read(fmt, amount)
   if type(fmt) == "number" then
      return readN(self, fmt)
   elseif fmt == "=" then
      return readAll(self, amount)
   elseif fmt == "*a" then
      local rv, err = readAll(self, self.ALLMAX)
      if err then
         return nil, err
      end
      return rv or ""
   elseif fmt == "*l" or fmt == "*L" or fmt == nil then
      return readLine(self, fmt == "*L")
   end

   error("bad argument to BufIO:read (invalid format)")
end


function BufIO:write(...)
   return self.f:write(...)
end


function BufIO:close()
   self.f:close()
end

return BufIO
