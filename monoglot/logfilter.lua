-- Log

local function wrap(handler)

   local function wrapper(request)
      print(request.method .. " " .. request.path)
      local r = table.pack( handler(request) )
      print(request.method .. " " .. request.path .. " -> " ..
               tostring(r[1]) .. " " ..
               (type(r[3])=="string" and #r[3] or "?"))
      return table.unpack(r)
   end
   return wrapper
end


return {
   wrap = wrap
}