
local function escapeChar(c)
   return string.format("\\%03d", c:byte())
end

-- Replace non-ASCII or non-printable characters with "\nnn" sequences
local function escape(str)
   str = str:gsub("\\", "\\\\")
   str = str:gsub("[\0-\9\11-\31\127-\255]", escapeChar)
   return str
end


-- Look up method `name` in `self.inner`, and populate `self` with
-- a wrapper method that calls `self.inner`.
--
local function wrapIndex(self, name)
   local inner = rawget(self, "inner")
   local ivalue = inner[name]
   if ivalue == nil then
      return nil
   end

   assert(type(ivalue) == "function")
   local value = function (self, ...)
      return ivalue(self.inner, ...)
   end

   self[name] = value
   return value
end


local LogSocket = {}

local wrapNum = 0

local function wrapSocket(inner, writeLine)
   local me = setmetatable({}, { __index = wrapIndex })
   me.inner = inner

   wrapNum = wrapNum + 1
   me._num = wrapNum
   me._writeLine = writeLine

   -- min-in LogSocket functions
   for k, v in pairs(LogSocket) do
      me[k] = v
   end
   return me
end


-- Log the results `values` of function `name` to `writeLine`
--
function LogSocket:_log(name, ...)
   local writeLine = self._writeLine
   local socketNum = self._num
   local methodName = "[" .. socketNum .. "]" .. name

   local numValues = select("#", ...)
   local value1 = select(1, ...)

   if numValues == 1 and type(value1) == "string" then
      local prefix = methodName .. ": "

      local data = escape(value1)
      local pos = 1
      while pos <= #data do
         local chunk = data:sub(pos, pos+79)
         local line = chunk:match("(.-)\n")
         if line then
            writeLine(prefix .. line)
            pos = pos + #line + 1
         else
            writeLine(prefix .. chunk .. "\\")
            pos = pos + #chunk
         end
      end
   else
      local o = { methodName, "->" }
      for n = 1, numValues do
         local v = select(n, ...)
         if type(v) == "string" then
            v = v:format("%q")
         else
            v = tostring(v)
         end
         table.insert(o, v)
      end
      writeLine(table.concat(o, " "))
   end
   return ...
end

function LogSocket:read(...)
   return self:_log("read", self.inner:read(...))
end

function LogSocket:write(...)
   assert(select("#", ...) == 1, "Too many arguments to `socket:write`")
   local buf = ...
   assert(type(buf) == "string", "Non-string argument to `socket:write`")
   local amt, err = self.inner:write(buf)
   if amt then
      self:_log("write", buf:sub(1,amt))
      return amt
   end
   return amt, err
end

function LogSocket:close(...)
   return self:_log("close", self.inner:close(...))
end

function LogSocket:shutdown(...)
   return self:_log("shutdown", self.inner:shutdown(...))
end

function LogSocket:accept(...)
   local values = table.pack(self.inner:accept(...))
   if values[1] then
      values[1] = wrapSocket(values[1], self._writeLine)
   end
   return self:_log("accept", table.unpack(values))
end


return {
   wrap = wrapSocket,
   -- for testing:
   _log = LogSocket._log,
   escape = escape
}
