-- JSON encoder/decoder
--
-- See json.txt for documentation.


local utf8utils = require "utf8utils"

local match, byte = string.match, string.byte

local json = {}

-- distinguished value for 'null'
json.null = function () end


local mtArray = {
   __index = table
}

-- Identify t as an array for future encodings.  Returns t.
--
function json.makeArray(t)
   setmetatable(t, mtArray)
   return t
end

function json.isArray(t)
   return type(t) == "table" and (t[1] or getmetatable(t) and getmetatable(t).__index)
end

-- Escape characters in string literals
local escapeChar = {
   ["\""] = "\\\"",
   ["\\"] = "\\\\",
   ["\n"] = "\\n",
   ["\r"] = "\\r",
   ["\t"] = "\\t",
   ["\f"] = "\\f",
   ["\b"] = "\\b",
}
function escapeChar:__index(k)
   local s = string.format("\\u%04x", byte(k))
   self[k] = s
   return s
end
setmetatable(escapeChar, escapeChar)


local nlstr = ""     -- line break string
local encodeKey


local function encode(x)
   if type(x) == "string" then
      return '"' .. x:gsub('[%c\\"]', escapeChar) .. '"'
   elseif type(x) == "boolean" or type(x) == "number" then
      return tostring(x)
   elseif type(x) == "table" then
      local res = { "" }
      local b1, b2 = '{', '}'
      if json.isArray(x) then
         b1, b2 = '[', ']'
         for _,v in ipairs(x) do
            table.insert(res, encode(v))
         end
      else
         for k,v in pairs(x) do
            if type(k) == "string" then
               table.insert(res, encodeKey(k)..":"..encode(v))
            end
         end
      end
      local str = table.concat(res, ","..nlstr)
      return b1 .. str:sub(2) .. nlstr .. b2
   else
      return "null"  -- nil, function, userdata, other?
   end
end


local function jsEncodeKey(k)
   return match(k, "^[%a_][%w_]*$") and k or encode(k)
end


-- Return JSON encoding of value
--   mode = string containing letters that enable options:
--     "n" : Insert newlines after object & array members.
--     "j" : Enable JavaScript mode: quote property names only when
--           needed by JavaScript (in JSON, they are always quoted).
--
function json.encode(v,mode)
   mode = mode or ""
   nlstr = mode:find("n") and "\n" or ""
   encodeKey = mode:find("j") and jsEncodeKey or encode
   return encode(v)
end


local unescapeChar = {
   [byte"\""] = "\"",
   [byte"\\"] = "\\",
   [byte"/"] = "/",
   [byte"n"] = "\n",
   [byte"r"] = "\r",
   [byte"t"] = "\t",
   [byte"f"] = "\f",
   [byte"b"] = "\b",
}


local decodeValues = {
   ["null"] = json.null,
   ["true"] = true,
   ["false"] = false,
}
setmetatable(decodeValues, { __index = function (t,k) return tonumber(k) end } )


local function decodeError(pos, expected)
   error("Expected " .. expected .. " at offset " .. pos, 2)
end


local function makeDecodeFrom(str, err, ...)
   decodeValues.null = select('#', ...) == 0 and json.null or (...)

   err = err or decodeError

   -- Read value at position `start` in `str`, returning v, c, n:
   --   v = read value, or nil on error
   --   c = char following the value and whitespace
   --   n = position in str following ch
   --
   local function decodeFrom(start)

      -- STRING

      local v,d,c,n = match(str, '^[ \t\n\r]*"([^\\"]*)("?)[ \t\n\r]*(.?)()', start)
      if v then
         if d == '"' then return v,c,n end
         while c == '\\' do
            c = unescapeChar[byte(str,n)]
            if c then
             v = v .. c
               n = n + 1
            else
               local u = match(str, "^u(%x%x%x%x)", n)
               if u then
                  v = v .. utf8utils.encode( tonumber(u, 16) )
                  n = n + 5
               else
                  err(n-1, "valid escape sequence")
               end
            end
            local txt
            txt, d, c, n = match(str, '([^\\"]*)("?)[ \t\n\r]*(.?)()', n)
            v = v .. txt
            if d == '"' then
               return v, c, n
            end
         end
         err(n, "end of string")
      end

      local v,c,n = match(str, "^[ \t\n\r]*([%[{]?)[ \t\n\r]*(.?)()", start)
      if v ~= "" then
         local elem
         if v == '{' then

            -- OBJECT

            v = {}
            if c ~= '}' then
               local key, nkey, n2
               n = n - 1
               repeat
                  nkey = n
                  -- optimisitically read a simple string followed by ":"
                  key, n = match(str, '^[ \t\n\r]*"([^\\"]*)"[ \t\n\r]*:()', n)
                  if not key then
                     -- handle not-so-simple strings
                     key, c, n = decodeFrom(nkey)
                     if type(key) ~= "string" then err(nkey, 'string') end
                     if c ~= ':' then err(n-1, ':') end
                  end
                  elem, c, n = decodeFrom(n)
                  v[key] = elem
               until c ~= ','
               if c ~= '}' then err(n-1, ', or }') end
            end

         else

            --  ARRAY

            v = json.makeArray{}
            local index = 1
            if c ~= ']' then
               n = n - 1
               repeat
                  elem, c, n = decodeFrom(n)
                  v[index] = elem
                  index = index + 1
               until c ~= ','
               if c ~= ']' then err(n-1, ', or ]') end
            end
         end
         return v, match(str, "^[ \t\n\r]*(.?)()", n)

      else

         -- NUMBER &  KEYWORDS (null, true, false)

         local tok
         tok, c, n = match(str, "^([^ \t\n\r,:%]}]*)[ \t\n\r]*(.?)()", n-1)
         v = decodeValues[tok]
         if v ~= nil or tok == "null" then
            return v, c, n
         end
         err(start, "value")
      end
   end

   return decodeFrom
end


function json.decode(str, ...)
   local function err(pos, expected)
      error("Expected " .. expected .. " at offset " .. pos, 0)
   end

   local decodeFrom = makeDecodeFrom(str, err, ...)
   local succ, v, c, n = pcall(decodeFrom, 1)

   if not succ then
      return nil, v
   end

   if c and c ~= "" then
      return nil, "Extraneous data at offset " .. n
   end
   return v
end


function json.decodeAt(str, n, ...)
   return makeDecodeFrom(str, decodeError, ...)(n)
end


function json.toAscii(str)
   local function esc(s)
      return "\\u" .. string.format("%04x", utf8utils.decode(s))
   end
   return ( str:gsub(utf8utils.mbpattern, esc) )
end


json.asciify = json.toAscii


return json
