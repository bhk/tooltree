
local function maxn(tbl)
   local max = 0
   for k in pairs(tbl) do
      if type(k) == "number" and k > max then
         max = k
      end
   end
   return max
end

return maxn
