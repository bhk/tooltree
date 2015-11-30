local unpack = table.unpack or unpack
local pack = table.pack or function (...) return { n=select("#",...), ...} end

local function myunpack(t, n)
   local max = t.n or #t
   n = n or 1
   if n <= max then
      return t[n], myunpack(t, n+1)
   end
end


local function f(...)
   return select("#", ...)
end

assert( f(1,nil) == 2 )

local p = pack(1,nil)

assert( f(myunpack(p)) == 2 )

assert( f(unpack(p, 1, p.n)) == 2 )

