local qt = require "qtest"
local ValueMap = require "valuemap"

local eq = qt.eq

local m = ValueMap:new(3)

local values = {
   "a",
   {"b"},
   true,
   false
}

local ids = {}


for n, v in ipairs(values) do
   local id = m:toID(v)
   eq("string", type(id))
   ids[n] = id
   eq(v, m:fromID(id))
end

eq(nil, m:fromID(ids[1]))
eq(values[2], m:fromID(ids[2]))
eq(ids[3], m:toID(values[3]))


-- weak tables

local mw = ValueMap:new()
for n = 1, 100 do
   mw:toID({})
end
collectgarbage()
eq(next(mw.map), nil)
eq(next(mw.xmap), nil)

