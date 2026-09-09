local qt = require "qtest"
local requirefile = require "requirefile"

local datafile = arg[1]

-- Successful load?
local src = requirefile("requirefile/requirefile_q.lua")
qt.eq(true, src:match("HGyrqzx9") ~= nil)

-- Throw error on mod not found
local succ, err = pcall(requirefile, "mEWEcfOzj8/x")
qt.eq(succ, false)
qt.match(err, "^requirefile: ")

-- Makefile must set REQUIREFILE_PATH to include .ok directory...
-- [Use (...) so dependency scanning won't fail]
local ok = (requirefile)("requirefile/" .. datafile)
qt.eq("DATA", ok)
