-- counter macro
--
-- Usage:  \counter{class:item}
-- Each 'item' will be assigned a unique number within its class

local m = require "memoize"

local function newClass(class)
   local n = 0
   return m.newTable(function (item) n = n+1 ; return n end)
end

local counts = m.newTable(newClass)

return function (node)
   local class, item = node.text:match("^([^ \n]*)[ \n]*(.*)")
   if not class then
      class, item = "", node.text
   end
   return tostring(counts[class][item])
end
