local qt = require "qtest"
local HTTPD = require "httpd"
local Dino = require "dino"
local trapFilter = require "trapfilter"
local thread = require "thread"
local doctree = require "doctree"
local getopts = require "getopts"
local json = require "json"
local observable = require "observable"
local owebserve = require "owebserve"

local E = doctree.E


----------------------------------------------------------------
-- Utilities
----------------------------------------------------------------

local function readFile(name)
   local f = io.open(name, "r")
   if f then
      local data = f:read("*a")
      f:close()
      return data
   end
end


local extToType = {
   css = "text/css",
   html = "text/html",
   js = "application/javascript",
   lua = "text/lua"
}


local function fileResponse(name, data)
   local ext = name:match("[^.]*$")
   local typ = extToType[ext] or "application/octet-stream"
   if data then
      return 200, {contentType = typ}, data
   end
   return 404, {contentType = "text/plain"}, "File not found: " .. name
end


local function readAll(s)
   local o = {}
   while true do
      local data = s:read(15000)
      if not data then break end
      o[#o+1] = data
   end
   return table.concat(o)
end


----------------------------------------------------------------
-- Web request handler
----------------------------------------------------------------

local mainPage
local entities = {
   a = observable.Slot:new(0),
   b = observable.Slot:new(0)
}
entities.c = observable.Func:new(function (a,b) return a+b end,
                                 entities.a,
                                 entities.b)


local dino = Dino:new()
local GET, PUT, POLL, POST =
   dino.method.GET, dino.method.PUT, dino.method.POLL, dino.method.POST

GET['/'] = function ()
   return fileResponse("oweb_demo.html", readFile(mainPage))
end


POLL['/observe'] = owebserve.serve(entities)


PUT['/set/*'] = function (req, _, name)
   local ob = entities[name]
   local body = readAll(req.body)
   if ob then
      ob:set( json.decode(body) )
   else
      return 400, {}, "Bad entity name"
   end
   return 200
end


dino.when[true] = function (request)
   return 404, {
      E.head {
         E.title { "Resource not found" },
      },
      E.h1 { "Resource not found" },
      E.pre { request.path }
   }
end


----------------------------------------------------------------
-- main
----------------------------------------------------------------

local function main()
   local words, opts = getopts.read(arg, "--ui --port=")

   assert(#words == 1, "No arguments passed!  Name file to serve as '/'.")
   mainPage = words[1]

   -- start server

   local port = opts.port or os.getenv("port") or ":8888"
   if not port:find(":") then
      port = ":" .. port
   end
   port = port:gsub("^:", "127.0.0.1:")
   local server = HTTPD:new(port)
   server:start(trapFilter.wrap(dino))
   io.write("Listening on " .. port .. " ...\n")

   -- launch browser if "--ui" was given

   if opts.ui then
      os.execute("open " .. "http://" .. port)
   end
end

thread.dispatch(main)
