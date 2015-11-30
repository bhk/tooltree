local mu = require "markup"
local doctree = require "doctree"


-- backward compat: support API documented in smark.txt
local function visitNodes(tree, ofType, fn)
   return doctree.visitElems(tree, fn, ofType)
end


return {
   parse = mu.parseDoc,
   expand = mu.expandDoc,
   E = doctree.E,
   TYPE = doctree.TYPE,
   visitNodes = visitNodes,
}
