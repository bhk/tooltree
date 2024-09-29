local HTTPD = require "httpd"
local Dino = require "dino"
local thread = require "thread"
local doctree = require "doctree"
local trapFilter = require "trapfilter"
local logFilter = require "logfilter"
local Target = require "target"
local getopts = require "getopts"
local json = require "json"
local O = require "observable"
local requirefile = require "requirefile"
local memoize = require "memoize"
local farf = require "farf"
local owebserve = require "owebserve"
local logsocket = require "logsocket"
local After = require "after"

local E = doctree.E


-- indicate "target not responding" after a command has not been
-- acknowledged for this long
local BUSY_LAG = 0.5

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
   if not data then
      return 404, {contentType = "text/plain"}, "File not found: " .. name
   end

   local hdrs = {}

   if name:match("%.gz$") then
      name = name:sub(1, #name - 3)
      hdrs.contentEncoding = "gzip"
   end

   local ext = name:match("[^.]*$")
   hdrs.contentType = extToType[ext] or "application/octet-stream"
   return 200, hdrs, data
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
-- Debugger State
----------------------------------------------------------------

local target
local oBreak = O.Slot:new({})

local function createObservable(name)
   local function jsonize(value)
      if type(value) == 'table' then
         value = json.makeArray(value)
      end
      return value
   end
   return O.Func:new(jsonize, target:observe(name))
end


local observables = memoize.newTable(createObservable)
observables.breakpoints = oBreak


local function createTarget(command)
   target = Target:new(command, oBreak)
   observables.console = target.log

   -- when busy for an entire second or more:
   local debounceBusy = After:new(target.busy, BUSY_LAG)

   local function calcMode(status, isBusy)
      return (isBusy and status ~= "exit") and "busy" or status
   end

   observables.mode = O.Func:new(calcMode, target.status, debounceBusy)
end


----------------------------------------------------------------
-- Web request handler
----------------------------------------------------------------

local dino = Dino:new()
local GET, PUT, POLL, POST =
   dino.method.GET, dino.method.PUT, dino.method.POLL, dino.method.POST


POLL['/observe'] = owebserve.serve(observables)


GET['/'] = function ()
   return fileResponse("mdbapp.html.gz", requirefile("mdb/mdbapp.html.gz"))
end


PUT['/breakpoints'] = function (req)
   local body = readAll(req.body)
   oBreak:set(json.decode(body))
   return 204
end


GET["/source"] = function (req)
   if not (req.params and req.params.name) then
      return 404
   end
   local file = req.params.name:gsub("%%2[eE]", "%.")
   return fileResponse(file, readFile(file))
end


GET['/run/{inOutOver}'] = function (req, m)
   target:run(m.inOutOver)
   return 204
end


GET['/pause'] = function ()
   target:pause()
   return 204
end


GET["/restart"] = function ()
   target:restart()
   return 204
end


POST['/console'] = function (req)
   local data = readAll(req.body)
   target:eval(data)
   return 204
end


GET['^/serve/(.+)'] = function (req, name)
   return fileResponse(name, readFile(name))
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


local function openBrowser(url)
   local f = io.popen("which xdg-open open", "r")
   local o = f:read("*a") or ""
   f:close()
   local cmd = o:match("[^\n]+") or "start"
   os.execute(cmd .. " " .. url)
end


local function main()
   local words, opts = getopts.read(arg, "--ui --port= --uri=")

   -- launch target process

   if not words[1] then
      io.write("mdb: no debug command given\n")
      return
   end

   createTarget(words)
   io.write("mdb: command = " .. table.concat(words, " ") .. "\n")

   -- start server

   local port = opts.port or os.getenv("port") or ":9779"
   if not port:find(":") then
      port = ":" .. port
   end
   port = port:gsub("^:", "127.0.0.1:")
   local server = HTTPD:new(port)
   if farf("s") then
      server.sock = logsocket.wrap(server.sock, print)
   end
   local handler = farf("w") and logFilter.wrap(dino) or dino
   server:start(handler) -- trapFilter.wrap(handler))
   io.write("mdb: listening on " .. port .. " ...\n")

   -- launch browser if "--ui" was given

   if opts.ui then
      openBrowser("http://" .. port .. "/" .. (opts.uri or ""))
   end
end

thread.dispatch(main)
