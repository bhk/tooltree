-- json_q.lua

local qt = require "qtest"
local json = require "json"

-- json.encode

function qt.tests.encode()
   local function e(a,...)
      return qt.eq(a, json.encode(...))
   end

   e("true", true)
   e("false", false)

   e("1", 1)

   e('"a"', "a")
   e('"a\\r\\n\\\\b\\t\\u001f"', "a\r\n\\b\t\31")

   e("null", json.null)

   e('[]', json.makeArray{})
   e('[1,2]', {1,2})
   e('[\n1,\n2\n]', {1,2}, "n")
   e('{"a":1}', {a=1})
   e('{\n"a":1\n}', {a=1}, "n")

   e('{a:1}', {a=1}, "j")
   e('{\na:1\n}', {a=1}, "jn")
end

-- json.decode

function qt.tests.decode()
   local function d(a,str)
      -- nothing but JSON string
      local v, c, n = json.decodeAt(str, 1)
      qt._eq(a, v, 2)
      qt._eq("", c, 2)
      qt._eq(#str + 1, n, 2)

      -- JSON in middle of string
      v,c,n = json.decodeAt("xx"..str..":", 3)
      qt._eq(a, v, 2)
      qt._eq(":", c, 2)
      qt._eq(#str + 4, n, 2)
   end

   d(1, '1')
   d(-1, '-1')
   d(-0.1e+2, '-0.1e+2')
   d(100e-2, '100e-2')

   d('', '""')
   d('a', '"a"')
   d('\\', '"\\\\"')
   d('\n', '"\\n"')
   d('\t', '"\\t"')
   d('\f', '"\\f"')
   d('\b', '"\\b"')
   d('"', [["\""]])
   d('\\', [["\\"]])
   d('\\ \n \t\f\r\\\"\b',  [["\\ \n \t\f\r\\\"\b"]])

   d('abc', '"a\\u0062c"')
   d('xaz', '"x\\u0061z"')

   d(true, "true")
   d(false, "false")
   d(json.null, "null")

   -- alternate "null" values

   qt.eq("ABC", json.decode("null", "ABC") )
   qt.eq(false, json.decode("null", false) )
   qt.eq(nil, json.decode("null", nil) )
   qt.eq({}, json.decode("[null]", nil) )
   qt.eq({nil,1}, json.decode("[null,1]", nil) )

   assert(json.isArray(json.decode("[]")))
   d({}, "[]")
   d({1}, "[1]")
   d({1,2}, "[1,2]")

   assert(not json.isArray(json.decode("{}")))
   d({}, '{}')
   d({a=1}, '{"a":1}')
   d({a=1,b={}},  '{"a":1,"b":[]}')

   -- whitespace

   d({a=1,b={}},  '\n {\n \n"a"\r\n:\n \n1\n,\n"b"\n:\n[\n]\n}\n')

   d({a={b=1},b={}},  '\n {\n \n"a"\r\n:\n \n{"b":1},\n"b"\n:\n[\n]\n}\n')


   -- multi-byte utf-8 sequences

   local char = string.char
   d( char(0xC2, 0x80),  '"\\u0080"' )
   d( char(0xDF, 0xBF),  '"\\u07FF"' )

   -- error cases

   local function e(str, pat)
      local succ, e = json.decode(str)
      qt._eq(nil, succ, 2)
      qt.match(e, pat)
   end

   e('{"a"}', "Expected : at offset 5")
   e('"a', "Expected end of string")
   e('"\\z"', "Expected valid escape sequence at offset 2")

   -- toAscii

   qt.eq( "a\\u0080", json.toAscii(char(97, 194, 128)))

   -- asciify (backwards compatibility)

   qt.eq( json.toAscii, json.asciify)

end

if arg[1] == "bench" then
   local C = require "clocker"
   local S = require "serialize"
   local txt = assert(io.open(arg[2])):read"*a"

   C:compare {
      function () json.decode(txt) end,
   }
end


return qt.runTests()
