-- Simple web server in Lua

local HTTPD = require 'httpd'
local thread = require 'thread'


local function handler(req)
   if req.method == 'GET' and req.path == '/hello' then
      return 200, {contentType = 'text/plain'}, 'Hello world'
   end

   return 404, {contentType = 'text/html'}, 'Resource not found'
end


local function main()
   local addr = arg[1] or ':8001'
   HTTPD:new(addr):start(handler)
   print('Listening on ' .. addr .. ' ...')
end

thread.dispatch(main)
