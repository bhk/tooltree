local qt = require "qtest"
local Dino = require "dino"


local eq = qt.eq

local dino, get, put, post, delete

local function init()
   dino = Dino:new()
   local m = dino.method
   get, put, post, delete = m.GET, m.PUT, m.POST, m.DELETE
end

local function dt(req, result)
   if type(req) == "string" then
      req = { path=req }
   end
   req.method = req.method or 'GET'
   return eq( dino:handle(req), result)
end


-- Globbing helper

local function globTest(pat, str, out)
   return eq( Dino.globToLPEG(pat):match(str), out)
end

globTest("asdf", "asdf", {})
globTest("sdf", "asdf", nil)
globTest("asd", "asdf", nil)

globTest("/{a}/*/{bcd}", "/AB/CD/EF", {"CD", a="AB", bcd="EF"})
globTest("/{a}/*/{bcd}", "/AB/CD/EF/", nil)


-- Routes

init()

get("/a", function (req) return 200 end)
put("/a", function (req) return 201 end)
post("/a", function (req) return 202 end)
delete("/a", function (req) return 203 end)

dt({method="GET", path="/a"}, 200)
dt({method="PUT", path="/a"}, 201)
dt({method="POST", path="/a"}, 202)
dt({method="DELETE", path="/a"}, 203)

-- alternate syntax

get["/"] = function (req) return "[/]" end
get["/"] = function (req) return "not overridden" end
get["/a/1"] = function (req) return "[/a/1]" end
get["/b/c"] = function (req) return "[/b/c]" end

dt({method="GET", path="/"}, "[/]")
dt({method="GET", path="/a/1"}, "[/a/1]")

dt({method="GET", path="/b"}, nil)
dt({method="GET", path="/c"}, nil)


-- Glob captures

get["/g/*/{name}"] = function (req, w, a)
   assert(a == w[1])
   return a .. "/" .. w.name
end

dt("/g/qwer/asdf", "qwer/asdf")


-- Lua Pattern Captures

get["^/c/([^/]*)/([^/]*)$"] = function (req, a, b)
   return a .. ":" .. b
end

dt("/c/d/efg", "d:efg")
dt("/c/d/e/f", nil)


-- Return values

get["/rv/b"] = function () return "B" end
get["/rv/h/b"] = function () return {}, "B" end
get["/rv/s/b"] = function () return 200, "B" end
get["/rv/s/h/b"] = function () return 200, {}, "B" end

local hh = { contentType = "text/html"}
eq({dino{method="GET", path="/rv/b"}}, {200, hh, "B"})
eq({dino{method="GET", path="/rv/h/b"}}, {200, hh, "B"})
eq({dino{method="GET", path="/rv/s/b"}}, {200, hh, "B"})
eq({dino{method="GET", path="/rv/s/h/b"}}, {200, hh, "B"})

-- auto-serialization of HTML

get["/serialize"] = function () return { "<a>" } end
local s, h, b = dino{method="GET", path="/serialize"}
qt.match(b, "&lt;a&gt;")

-- 'when' handlers

local function hasXXX(req)
   return req.XXX
end

dino.when[hasXXX] = function (req)
   return "hasXXX"
end

dino.when[true] = function (req)
   return 404, {}, "notfound"
end

local s, h, b = dino{ method="GET", path="/undefined", XXX=1 }
eq(s, 200)
eq(b, "hasXXX")

local s, h, b = dino{ method="GET", path="/undefined"}
eq(s, 404)
eq(b, "notfound")


-- `body` alternative: stream function

init()

local function streamBody(emit)
   emit "Hello"
end

get["/stream"] = function (req)
   return streamBody
end

s, h, b = dino{ method="GET", path="/stream" }
eq(streamBody, b)
eq(h.contentLength, nil)


-- params

init()

get["/x"] = function (req)
   return req.params.name
end

s, h, b = dino{ method="GET", path="/x", query="?name=a%2fb" }
eq(b, "a/b")
