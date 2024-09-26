# cfromlua test (sh comment first-line)

local requirefile = require "requirefile"

local hasPreload = (kilroyWasHere and "P1" or "P0")
local hasDebug = ((require "debug") and "D1" or "D0")

-- dep should be executed only once (d0 == d1 == 1)
local d0 = require "dep"
local d1 = require "dep"

-- get file data (from dir that contains "dep" module)
local m1 = requirefile("dep/dep.lua")
local m2 = requirefile("dep/data.txt")
-- require twice (should be one copy when bundle)
requirefile("dep/data.txt")

if arg == "Test" then
   return
end

print("<" .. (os.getenv("LUA_PATH") or "") .. ">")

print(hasPreload .. "," ..
         hasDebug .. "," ..
         (arg[1] or "") .. "," ..
         d1 .. "," ..            -- "1"
         m1:sub(1,10) .. "," ..  -- "-- dep.lua" or "BOGUS"
         m2:sub(1,12))           -- "This is data" or "BOGUS"
