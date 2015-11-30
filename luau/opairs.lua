-- Sorted version of pairs()
--
-- Unlike pairs(), the results of opairs() can be ordered deterministically.
-- This is valuable when ordering is observable in the output of a program
-- or module. Non-deterministic results can complicate testing and interface
-- definitions.
--
-- Usage:   for k, v = opairs(tbl) do ... end
--

local function defaultCmp(a, b)
   local ta, tb = type(a), type(b)
   if ta ~= tb then
      return ta < tb
   end
   if ta == "string" or ta == "number" then
      return a < b
   end
   return tostring(a) < tostring(b)
end

local function opairs(tbl, cmp)
   local keys = {}
   for k in pairs(tbl) do
      keys[#keys+1] = k
   end
   table.sort(keys, cmp or defaultCmp)

   local n = 1

   return function ()
      local k = keys[n]
      if k ~= nil then
         n = n + 1
         return k, tbl[k]
      end
   end
end

return opairs
