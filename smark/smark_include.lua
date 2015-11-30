
local function expand(node, doc)
   local filename = node.text:gsub("^%s*(.-)%s*$", "%1")
   return doc.parse( node._source:newFile(filename) )
end

return {
   expand = expand
}
