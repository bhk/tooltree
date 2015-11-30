local qt = require "qtest"
local mdbser = require "mdbser"

local encode, decode = mdbser.encode, mdbser.decode

local function roundTrip(value)
   local o = encode(value)
   qt.eq(nil, ( o:match("[\r\n]") ))
   qt.eq(value, decode(o))
end

-- simple values

roundTrip(nil)
roundTrip(true)
roundTrip(false)
roundTrip(-123.456)

qt.eq("x x", encode(nil, nil))
qt.eq( {nil, 1, nil, 5}, { decode(encode(nil, 1, nil, 5)) })

-- strings

roundTrip ""
roundTrip "abc"
roundTrip "\r\n"
roundTrip "\255"
roundTrip "\255\255"
roundTrip "\255\255\255"
roundTrip "\255."
roundTrip "\255\n"
roundTrip "\n\n\n"
roundTrip "\n\255"
roundTrip "\n.\255"

local s = ""
for n = 0, 255 do
   s = s .. string.char(n)
end
roundTrip(s)


-- tables

roundTrip {1, 2, 3}

roundTrip {a=true, b=false, [5]={"a b", "c d"}}


