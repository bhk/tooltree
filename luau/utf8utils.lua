-- utf8 encoding/decoding
--
-- See utf8utils.txt for documentation.


local char = string.char
local byte = string.byte
local match = string.match
local modf = math.modf

----------------------------------------------------------------
-- Convert character index to utf-8 byte string
----------------------------------------------------------------

local function encode(n)
   if n <= 0x7F then
      return char(n)
   end
   if n <= 0x7FF then
      local a
      a, n = modf(n / 64)
      return char(192+a, 128+n*64)
   end
   if n <= 0xFFFF then
      local a,b
      a,n = modf(n / 4096)
      b,n = modf(n * 64)
      return char(224+a, 128+b, 128+n*64)
   end
   if n <= 0x10FFFF then
      local a,b,c
      a,n = modf(n / 262144)
      b,n = modf(n*64)
      c,n = modf(n*64)
      return char(240+a, 128+b, 128+c, 128+n*64)
   end
   error("utf8: bad argument #1 to 'encode'")
end


-- This Lua pattern matches valid and invalid utf-8 multi-byte sequences
--
local mbpattern = "[\128-\255][\128-\191]*"

----------------------------------------------------------------
-- Convert utf-8-encoded character to numeric value
----------------------------------------------------------------

local function decode(s, ferr)
   -- assuming a >= 192, b in [128, 191]
   local n, min
   if match(s, "^[\192-\223][\128-\191]$") then
      -- two-byte sequence
      n = (byte(s,1)-192)*64 + byte(s,2) - 128
      min = 0x80
   elseif match(s, "^[\224-\239][\128-\191][\128-\191]$") then
      -- three-byte sequence
      n = ((byte(s,1)-224)*64 + byte(s,2)-128)*64 + byte(s,3)-128
      min = 0x800
   elseif match(s, "^[\240-\244][\128-\191][\128-\191][\128-\191]$") then
      -- four-byte sequence
      n = (((byte(s,1)-240)*64 + byte(s,2)-128)*64 + byte(s,3)-128)*64 + byte(s,4)-128
      min = 0x10000
   elseif match(s, "^[%z-\127]$") then
      -- single-byte sequence
      n = byte(s,1)
      min = 0
   else
      n = -1
      min = 0
   end
   if n >= min then
      return n
   end
   if (ferr) then
      return ferr(n, s)
   else
      error("utf8utils: invalid byte sequence")
   end
end


----------------------------------------------------------------
-- Throw an error if 'str' is not valid utf-8 as per RFC 3629
----------------------------------------------------------------

local function validate(str)
   for s in str:gmatch(mbpattern) do
      decode(s)
   end
end

----------------------------------------------------------------
-- Convert binary data to/from utf-8 encoded character data
----------------------------------------------------------------

local gsub = string.gsub

local function b2c(c)
   local n = byte(c)
   if n < 192 then
      return "\194"..c
   end
   return "\195" .. char(n-64)
end

local function binToChars(str)
   return ( gsub(str, "[\128-\255]", b2c) )
end


local function c2b(s)
   return char( (byte(s)-194)*64 + byte(s,2) )
end

local function charsToBin(str)
   return ( gsub(str, "[\194\195][\128-\255]", c2b) )
end


return {
   encode = encode,
   decode = decode,
   validate = validate,
   mbpattern = mbpattern,
   binToChars = binToChars,
   charsToBin = charsToBin
}
