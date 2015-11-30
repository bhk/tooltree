-- mdbser: a simple Lua serialization/deserialization library.
--
-- * Only booleans, strings, numbers, and tables are supported.
-- * Circular data structures are not supported.
-- * The encoded form of a value contains no spaces or newline characters.
--

local byte, char = string.byte, string.char
local insert, concat = table.insert, table.concat

local ESC = char(128)


local function escape(c)
   return ESC .. char(64 + byte(c))
end

local function unescape(cc)
   return char( byte(cc,2) - 64 )
end

local function shift(c)
   return char(byte(c)+1)
end

local function unshift(c)
   return char(byte(c)-1)
end


-- Escape spaces and newlines in str.
--
local function demote(str)
   return ( str:gsub('[ \r\n\128\191]', escape):gsub('[\128-\190]', shift) )
end


-- Undo `demote`
--
local function promote(str)
   return ( str:gsub('[\129-\191]', unshift):gsub('\128.', unescape) )
end


-- encode a Lua value as a word
--
local function encodeValue(value)
   local typ = type(value)

   if typ == "string" then
      return 's' .. demote(value)
   elseif typ == "boolean" then
      return value and 't' or 'f'
   elseif typ == "number" then
      return 'n' .. tostring(value)
   elseif typ == "table" then
      local o = {'m'}
      for k, v in pairs(value) do
         insert(o, encodeValue(k))
         insert(o, encodeValue(v))
      end
      return demote(concat(o, ' '))
   else
      return 'x'
   end
end


-- decode an arbitrary Lua value from a word
--
local function decodeValue(str)
   local ty = str:sub(1,1)

   if ty == 's' then
      return promote(str:sub(2))
   elseif ty == 'n' then
      return tonumber(str:sub(2))
   elseif str == 't' then
      return true
   elseif str == 'f' then
      return false
   elseif ty == 'm' then
      local t = {}
      for ekey, eval in promote(str):gmatch(" ([^ ]*) ([^ ]*)") do
         t[decodeValue(ekey)] = decodeValue(eval)
      end
      return t
   end

   return nil
end


-- Encode arguments (zero or more) as a string of space-delimited words.
--
local function encode(...)
   local o = {}
   for n = 1, select('#', ...) do
      o[#o+1] = encodeValue(select(n, ...))
   end
   return table.concat(o, " ")
end


-- Decode a string of space delimited words and return the resulting values.
--
local function decode(str, pos)
   local word, pnext = str:match('([^ ]+)()', pos or 1)
   if word then
      return decodeValue(word), decode(str, pnext)
   end
end


return {
   encode = encode,
   decode = decode
}
