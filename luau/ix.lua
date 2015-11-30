-- Utilities for interactive shells
--
local qt = require "qtest"

local shadowGlobals = {}

local function setGlobal (table, key, value)
   shadowGlobals[key] = value
   qt.printf("=> %s = %Q\n", tostring(key), value)
end

local function getGlobal (table, key)
   return shadowGlobals[key]
end

rawset(_G, "p", function(val) print(qt.describe(val)) end)
rawset(_G, "qt", qt)

setmetatable(_G, {  __newindex = setGlobal,
                    __index    = getGlobal })
