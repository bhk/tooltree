-- minimal smark macro implementation
local M = {}

function M:new(node)
   return node.text:upper()
end

return M
