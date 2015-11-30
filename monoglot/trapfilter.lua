-- trapfilter: web handler "filter" or "wrapper"
--
-- trapfilter traps errors thrown by the wrapped handler, returning
-- a description of the error suitable for debugging.

local doctree = require "doctree"
local HTMLGen = require "htmlgen"

local E = doctree.E

local css = [[
body { font: 12pt "Helvetica", "Arial", sans-serif; }
.pre { white-space: pre; font: 11pt "Lucida Console", "Courier", monospace; }
]]


local function wrap(handler)
   local function wrapper(request)
      local succ, a, b, c = xpcall(handler, debug.traceback, request)
      if succ then
         return a, b, c
      end

      local body = HTMLGen.generateDoc {
         E.head {
            E.title { "Error in Handler" },
            E.style { css }
         },
         E.body {
            E.h2 { "Error in Handler" },
            E.div {
               class = "pre",
               a
            }
         }
      }
      io.write(a)

      return 501, {contentType= "text/html"}, body
   end

   return wrapper
end


return {
   wrap = wrap
}
