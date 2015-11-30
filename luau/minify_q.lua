-- minify_q

local qt = require "qtest"
local mfy = require "minify"

local parse, strip = mfy.parse, mfy.strip

----------------------------------------------------------------
-- parse tests
----------------------------------------------------------------

local function parsecat(str)
   local s = ""
   local function emit(type, substr)
      s = s .. type:sub(1,1):upper() .. substr
   end
   parse(str, emit)
   return s
end

local function t(txt)
   return qt.eq(txt, parsecat(txt:gsub("[PSC]", "")))
end

function qt.tests.parse()

   t "Pabc"
   t "PabcS'abc'"
   t "PabcS'abc'C--xx"

   t [==[Px = 1 C-- comment
P  a = S"x \" y ' z [[a]]"P
   b = S'x " y \' z [[b]]'P
   c = S[[x " y ' z]]P
   d = S[=[x " y ' z]] ]=]P
   x = C--[=[comment]=]P

   ]==]

end


function qt.tests.parseError()
   local function noop() end
   qt.eq( {nil, "string", 5},  {parse("a'b'\"abc\\\"yz", noop)})
   qt.eq( {nil, "long comment", 5},  {parse("a'b'--[[xyz", noop)})
   qt.eq( {nil, "long string", 5},  {parse("a   [[xyz", noop)})
end


----------------------------------------------------------------
-- strip tests
----------------------------------------------------------------


function qt.tests.strip()
   qt.eq("a(1,2)", strip(" a ( 1  ,  2  )  "))
   qt.eq("\n\n\n", strip("--comment\n   --comment\n--comment\n"))
end



local function whatline(str, sub)
   local pre = str:match("(.-)"..sub)
   return select(2, pre:gsub("\n", "%1")) + 1
end

qt.eq(3, whatline("\n\nXXX", "XXX"))

local function t2(str)
   return qt.eq(whatline(str, "XXX"),  whatline(strip(str), "XXX"))
end


function qt.tests.stripLines()

   t2 [==[
-- this is a comment
a = 1  -- end of line comment
b = 2  --[=[ long
  comment
  another -- end of line
"\"
]=]
c = [[
[===[
empty line
]===]
]]
'
'
XXX
   ]==]
end

function qt.tests.stripEval()

   local function eval(str)
      local t = {print=print}
      local f = assert(load(str, nil, nil, t))
      return f()
   end

   local function ts(str)
      local a = eval(str)
      local b = eval(strip(str))
      return qt.eq(a, b)
   end


   ts [===[
a = 1
ab = 2--4
a = a--[[ c ]]b = 1
if a==1 then
   a = (a + 1)
end
function f(a)
   return function(x)
             if x then
                return f(a+x)
             end
             return a
          end
end
g = f(1)(2)--[[comment]](4)(a)
return g()
   ]===]
end

function qt.tests.stripError()
   qt.eq( {nil,"string",4}, {strip("abc'xyz")} )
end


--local s = io.open("../pakman/pm.lua"):read("*a")
--print(#s)
--print(#strip(s))
--print(strip(s))

return qt.runTests()
