-- testmemoize.lua : tests for memoize.lua

local qt = require "qtest"
local memoize = require "memoize"

local tests = qt.tests

local function CountCalls()
   local n = 0
   return function(str)
	     n = n + 1
	     return str .. tostring(n)
	  end
end


function tests.newTable()
   local t = memoize.newTable( CountCalls() )

   assert( t.a == "a1" and
	   t.b == "b2" and
	   t.a == "a1" and
 	   t.c == "c3" )

   qt.eq("a1", t("a") )
end

function tests.newFunction()
   -- make sure cacehed values are used
   local f = memoize.newFunction(table.remove)
   local t = {'a','b','c','d'}

   -- first time
   assert( f(t,3) == 'c')
   assert( f(t,2) == 'b')
   assert( f(t) == 'd' )
   assert( f(t,1) == 'a')

   -- second time: should be the same
   assert( f(t,3) == 'c')
   assert( f(t,2) == 'b')
   assert( f(t) == 'd' )
   assert( f(t,1) == 'a')

   -- nil args
   local g = memoize.newFunction(function (...) return select(...) end)

   assert( g(2,nil,3) == select(2,nil,3) )
   assert( g(1,nil,3) == select(1,nil,3) )
   assert( g('#',nil,3,nil) == select('#',nil,3,nil) )

   -- multiple return values
   local h = memoize.newFunction(function (...)
                                    return ...
                                 end)

   qt.eq(table.pack(h(1,nil,2)), {n=3,1,nil,2})
   qt.eq(table.pack(h(1,nil,2)), {n=3,1,nil,2})
   qt.eq(table.pack(h(1,nil)),   {n=2,1,nil})
   qt.eq(table.pack(h(1,nil)),   {n=2,1,nil})
   qt.eq(table.pack(h(1)),       {n=1,1})
end

function tests.curry()
   local c = memoize.curry
   assert( c(string.format)("%d", 3) == "3" )
   assert( c(string.format, "%d")(1) == "1" )
   assert( c(string.format, "%d%d", 1)(2) == "12" )

   assert( c(tostring, nil)() == "nil" )
   assert( c(tostring, true)() == "true" )
   assert( c(tostring, false)() == "false" )

   local tr = c(table.remove, {1,2,3})

   assert( c(table.remove) == c(table.remove) )
   assert( c(table.remove, 2) == c(table.remove, 2) )
end

-- Performance comparison

local clocker = require "clocker"
local c
local function ftimed(n) return n end


-- This doesn't use __index.  A bit slower on hits, faster on hits.
--
function memoize.newFunction1Alt(f)
   local t = {}
   setmetatable(t, { __mode = "k" } )
   return function(x)
     local y = t[x]
     if y == nil then
        y = f(x)
        t[x] = y
     end
     return y
   end
end


local function time()
   local tt = {
      { "true",         "calibrate" },
      { "tMemo['x']",   "table[hit]" },
      { "tMemo('x')",   "table(hit)" },
      { "fMemo('x')",   "func(hit)" },
      { "tMemo[n]",     "table[miss]" },
      { "tMemo(n)",     "table(miss)" },
      { "fMemo(n)",     "func(miss)" },
      { "fMemo('x','y')",  "func(hit X 2)" },
      { "fMemo(n,n)",      "func(miss X 2)" },
      { "f1aMemo('x')",  "func1a(hit)" },
      { "f1aMemo(n)",    "func1a(miss)" },
   }

   for _,t in ipairs(tt) do
      local env = {
         n = 0,
         tMemo = memoize.newTable(ftimed),
         f1aMemo = memoize.newFunction1Alt(ftimed),
         fMemo = memoize.newFunction(ftimed)
      }
      local f = loadstring("n = n + 1 ; return " .. t[1])
      setfenv(f, env)
      env.n = 0
      collectgarbage()
      if t[2] == "calibrate" then
         clocker:init(f)
      else
         c = clocker:time(f)
         c:show(t[2], true)
      end
   end
end

--tests.time = time

return qt.runTests()
