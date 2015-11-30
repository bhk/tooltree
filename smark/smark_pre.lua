-- '.pre' macro

return function (node)
   local E = require("smarklib").E
   return E.pre{ node.text }
end
