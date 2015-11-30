local qt = require "qtest"
local Object = require "object"
local BufIO = require "bufio"

local eq = qt.eq


local File = Object:new()


function File:read(n)
   assert(type(n) == "number")

   local buf = self[1]
   if not buf then
      return nil -- end of stream
   end

   local rest = buf:sub(n+1)
   if rest ~= "" then
      self[1] = rest
   else
      table.remove(self, 1)
   end
   return buf:sub(1,n)
end


function File:push(...)
   for _, str in ipairs{...} do
      table.insert(self, str)
   end
end


function File:initialize(...)
   self:push(...)
end


-- check File
local f = File:new("abc", "de")
eq("abc", f:read(100))
eq("de", f:read(100))
eq(nil, f:read(100))


local function stack(strings, opts)
   local b = BufIO:new(File:new( table.unpack(strings) ))
   for k,v in pairs(opts or {}) do
      b[k] = v
   end
   return b
end



-- "*l" and "*L" and default

eq(stack{"this is ", "a", "\n", "test"}:read('*l'),
   "this is a")

eq(stack{"this is ", "a", "\n", "test"}:read(),
   "this is a")

eq(stack{"this is ", "a", "\n", "test"}:read('*L'),
   "this is a\n")

eq(stack{"this is ", "a\r", "\n", "test"}:read('*L'),
   "this is a\r\n")

eq( {stack({"this is a test\n"}, {LINEMAX=8}):read()},
    {nil, "maximum line length exceeded"})


-- "*a"

eq(stack({"this ", "is ", "a", " test\n", "of the"}):read("*a"),
   "this is a test\nof the")

-- when at end, '*a' returns "", not nil

eq(stack({}):read('*a'), "")

-- <number>

eq(stack{"abcd", "ef"}:read(5),
   "abcd")

eq(stack{"abcde", "f"}:read(5),
   "abcde")

eq(stack{"abcdef", "g"}:read(5),
   "abcde")

eq(stack{"", "", "abcdefghijklnop"}:read(5),
   "abcde")


-- "=" <number>

local b = stack{"a", "bcd", "efg", "h"}
eq(b:read("=", 5),
   "abcde")
eq(b:read("=", 3),
   "fgh")

b = stack{"a", "bcd", "efg", "h"}
eq(b:read("=", 1),
   "a")
eq(b:read("=", 1),
   "b")

