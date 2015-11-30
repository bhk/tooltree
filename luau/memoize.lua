----------------------------------------------------------------
-- Memoize: Utilities for memoization
----------------------------------------------------------------


local function callTable(t,k)
   return t[k]
end

-- netTable: Create a table that memoizes a function. The memoized function
-- must take one non-nil argument and return one non-nil value.
--
-- The resulting table can also be invoked as a function.
--
-- Most commonly, memoization is used when you have a *pure* function, which
-- will always return the same results given the same inputs.  Given the
-- existence of references and mutability in Lua, however, you should be
-- aware that the lookup of previous results is based purely on the single
-- argument (not its contents when it is a table).  So for example,
-- newTable( tostring ) would be valid even when it operates on tables,
-- whereas newTable( table.sort ) would not.
--
-- To allow garbage collection to reclaim storage used by the memo table,
-- pass a non-nil value for weak (as defined for metatable __mode).
--
-- Usage:
--
--    t = newTable( math.sqrt )
--    print(t[4])  -->  2
--
local function newTable(f,weak)
   local function index(t,k)
      local x = f(k)
      t[k] = x
      return x
   end
   return setmetatable({}, { __mode = weak, __index = index, __call = callTable} )
end


-- Memoizing curry:
--
--    curry(f,argsA)(argsB)  ==  f(argsA,argsB)
--
-- argsA and argsB each represent zero or more arguments.  Additionally,
-- curry is memoized: it will always return the same value when passed the
-- same function and args.
--
-- The following simpler version does not memoize or handle nil args:
--
--    local function curry(f,a,...)
--       if a then
--          return curry(function (...) return f(a,...) end, ...)
--       end
--       return f
--    end

local NIL = {}

local combine = newTable(function (f)
   return newTable(function (a)
      if a == NIL then a = nil end
      return function (...) return f(a,...) end
   end)
end)

local function curry(f,...)
   for n = 1, select('#',...) do
      local v = select(n,...)
      f = combine[f][v==nil and NIL or v]
   end
   return f
end


-- Memoize a function with an arbitrary number of arguments and return
-- values.  nil values are handled properly.
--
local function newFunction(f)
   local values = newTable(function (f) return table.pack(f()) end)
   return function (...)
      local o = values[curry(f,...)]
      return table.unpack(o, 1, o.n)
   end
end


return {
   newTable = newTable,
   newFunction = newFunction,
   curry = curry
}
