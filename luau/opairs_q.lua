local qt = require "qtest"
local opairs = require "opairs"


local t = {}
for n = 1, 10 do
   t[string.char(64 + n)] = n % 3
end

local str = ""
for k, v in opairs(t, function (a,b) return a > b end) do
   str = str .. k .. v .. ","
end

qt.eq(str, "J1,I0,H2,G1,F0,E2,D1,C0,B2,A1,")



local tmix = {
   [false] = ".F",
   [true] = ".T",
   [1] = ".1",
   [2] = ".2",
   [10] = ".10",
   [9] = ".9",
   A = ".A",
   B = ".B"
}

local str = ""
for k, v in opairs(tmix) do
   str = str .. tostring(k) .. v .. ","
end

qt.eq(str, "false.F,true.T,1.1,2.2,9.9,10.10,A.A,B.B,")

