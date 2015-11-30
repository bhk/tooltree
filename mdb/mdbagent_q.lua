local qt = require "qtest"
local TE = require "testexe"
-- @require testtarget

local eq = qt.eq

local verbose = os.getenv("mdbagent_q_v")


-- find lua executable
local lua
for n = 0, -99, -1 do
   if not arg[n-1] then
      lua = arg[n]
      break
   end
end


-- Compare target program output in three different scenarios:
--
--    lua testtarget.lua
--    lua mdbagent.lua testtarget.lua
--    lua -l mdbagent testtarget.lua


-- Ignore extra "tail call" stack entry that mdbagent adds
local function prunelines(str)
   local a = TE.lines(str)
   return TE.grep(a, "tail calls", true)
end


local e = TE:new(lua, verbose)
e:exec("testtarget.lua fail")
local refErr = prunelines(e.stderr)
local refOut = e.out
eq(e.out, "")

e:exec("mdbagent.lua testtarget.lua fail")
eq(refErr, prunelines(e.stderr))
eq(refOut, e.out)


e:exec("-l mdbagent testtarget.lua fail")
eq(refErr, prunelines(e.stderr))
eq(refOut, e.out)


e:exec("testtarget.lua ok abc")
local refOut = e.out
local refErr = e.stderr

e:exec("mdbagent.lua testtarget.lua ok abc")
eq(refOut, e.out)
eq(refErr, e.stderr)

e:exec("-l mdbagent testtarget.lua ok abc")
eq(refOut, e.out)
eq(refErr, e.stderr)
