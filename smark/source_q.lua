local qt = require "qtest"
local Source = require "source"

-- Source:where

local sData = "ab\ncde\nfghi\n"
local s = Source:newFile("F", sData)

local function tw(posOut, fileSource, pos, line, col)
   qt._eq("F", fileSource.fileName, 2)
   qt._eq(posOut, pos, 2)
end

tw(nil, s:where(nil))
tw(nil, s:where(0))
tw(6, s:where(6))

-- line and col
local f, p, l, c = s:where(6)
qt.eq(2, l)
qt.eq(3, c)

-- Source:warn

local errors = {}
function s:printError(message, source, pos, line, col)
   table.insert(errors, {message, source.data, source.fileName, pos, line, col})
end
s:warn(6, "%sB", "A%s")
qt.eq({{"A%sB", sData, "F", 6, 2, 3}}, errors)

-- Source:extract

local a = Source:newFile("F", "abcdefghijklmnopqrstuvwxyz")

local b = a:extract(1, {{2,3},{6,8}}, "\n")

qt.eq(1, b.parentPos)
qt.eq("bc\nfgh\n", b.data)

local function r(...)
   local t = {...}
   table.remove(t,1)
   return t
end

tw(2, b:where(nil))
tw(2, b:where(0))

tw(2, b:where(1))
tw(3, b:where(2))
tw(4, b:where(3))   -- suffixed "\n"
tw(6, b:where(4))
tw(9, b:where(7))   -- suffixed "\n"

tw(1, b:where(8))   -- beyond end of data

-- Nested Extract

local c = b:extract(1, {{4,6}})  -- [4] = 'f' = F[6]

tw(6, c:where(1))
tw(6, c:where(nil))


return qt.runTests()
