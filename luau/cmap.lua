-- cmap:
--
-- cmap defines a set of functions that construct other functions that
-- perform 'map' operations over tables.  See cmap_q.lua for examples
-- and documentation.
--

local memo = require "memoize"

local tmpl = [[
local _p, _s, _f = ...
return function (_t)
  local _o = {}
  for k,v in _p(_t) do _s(_o,EXP) end
  return _o
end
]]

local function newMap(pairs, args, insert)
   local function compileMap(exp)
      local str = tmpl:gsub("EXP", type(exp)=="string" and exp or args)
      return assert(load(str, "(cmap auto-gen code)"))(pairs, insert, exp)
   end
   return memo.newTable(compileMap)
end

-- table.insert() accepts two OR THREE parameters, making for unintended and
-- very confusing results when the user-supplied function accidentally
-- returns more than one result.
local function append(t, v)
   t[#t+1] = v
end

return {
   i  = newMap(ipairs, "_f(v,k)", append),
   ix = newMap(ipairs, "_f(v,k)", rawset),
   x  = newMap(pairs,  "_f(k,v)", rawset),
   xi = newMap(pairs,  "_f(k,v)", append),
}
