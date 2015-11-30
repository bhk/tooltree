--
-- This is a simple web server built using monoglot
--

local HTTPD = require "httpd"
local Dino = require "dino"
local thread = require "thread"
local opairs = require "opairs"
local doctree = require "doctree"
local trapFilter = require "trapfilter"

local E = doctree.E


local defaultCSS = [[
body { font: 14px Arial; }
table { border-collapse: collapse; border-width: 1px; border-spacing: 1px;
   border-color: transparent; margin: 16px 0; }
th { background-color: #ddd; color: black; text-align: left; }
td, th { border-style: solid; border-color: #bbb; border-width: 1px;
   padding: 0 6px; font: 12px Courier; }}
td p:first-child, th p:first-child { margin-top: 3px; }
td p:last-child, th p:last-child { margin-bottom: 3px; }
th { white-space: nowrap; }
pre { background-color: #eee; color: black; border: 1px solid #888;
   padding: 2px; font: 12px Courier, monospace; }
]]

local style = E.style { defaultCSS }


-- Output contents of a Lua table as an HTML table
local function showTable(t)
   if not t then
      return E.i { "-nil-" }
   end
   local node = E.table {}
   for name, value in opairs(t) do
      if (type(name) == "string" or type(name) == "number") then
         if type(value) ~= "string" and type(value) ~= "number" then
            value = "<" .. type(value) .. ">"
         end
         node[#node+1] = E.tr {
            E.th { tostring(name) },
            E.td { tostring(value) }
         }
      end
   end
   return node
end


-- Output contents of a read stream as a PRE element
local function showStream(stream)
   local node = E.pre {}
   repeat
      local data, err = stream:read(4096)
      if data then
         node[#node+1] = data
      elseif err then
         return error(err)
      end
   until not data
   return node
end


-- Output contents a request object as HTML
local function showRequest (request)
   return {
      E.head {
         E.title { "Request Details" },
         style
      },
      E.h2 { "request[]" },
      showTable(request),
      E.h2 { "request.headers[]" },
      showTable(request.headers),
      E.h2 { "request.context[]" },
      showTable(request.context),
      E.h2 { "request.params[]" },
      showTable(request.params),
      E.h2 { "request.body" },
      (request.body
          and showStream(request.body)
          or E.i { "nil" }),
   }
end


local welcome = {
   E.head {
      E.title { "Welcome" },
      style
   },
   E.h1 { "Home" },
   E.h2 { "Link" },
   E.p { E.a { href = "/show", "Show request details" } },
   E.h2 { "GET form" },
   E.p {
      E.form {
         method = "GET",
         action = "/show",
         E.input { type = "text", name = "a", },
         E.input { type = "submit", name = "b", value = "submit" },
      }
   },
   E.h2 { "POST form" },
   E.p {
      E.form {
         method = "POST",
         action = "/show",
         E.input { type = "text", name = "a", },
         E.input { type = "submit", name = "b", value = "submit" },
      }
   },
   E.h2 { "Error" },
   E.p { E.a { href = "/error", "Uncaught error in handler" }},
   E.p { E.a { href = "/slow", "Slow reponse" } },
}


-- HTTPD instance
local server


-- Initialize Dino handler

local dino = Dino:new()
local GET, POST = dino.method.GET, dino.method.POST


GET["/"] = function ()
   return welcome
end


GET["/show"] = showRequest


POST["/show"] = showRequest


GET["/error"] = function (request)
   return "x" / 0
end


GET["/slow"] = function (request)

   local function body(emit)
      emit( "<title>Slow</title>" )
      for n = 1, 20 do
         thread.sleep(0.25)
         emit( "<div>"  .. n .. "</div>" )
      end
   end

   return body
end


GET["/exit"] = function (request)
   server:stop()
   return 200, E.h2 { "Exiting..." }
end


dino.when[true] = function (request)
   return 404, {
      E.head {
         E.title { "Resource not found" },
         style
      },
      E.h1 { "Resource not found" },
      E.pre { request.path }
   }
end


local function main()
   local port = os.getenv("port") or "127.0.0.1:8080"
   server = HTTPD:new(port)
   server:start(trapFilter.wrap(dino))
   print("Listening on " .. port .. " ...")
end

thread.dispatch(main)
