-- simple smark macro implementation

return function (node)
   local f = assert(io.popen(node.text, "r"))
   local txt = assert(f:read"*a")
   f:close()
   return { type="pre", txt }
end
