-- Dino: convenience class for constructing web handlers

local Object = require "object"
local memoize = require "memoize"
local htmlgen = require "htmlgen"
local lpeg = require "lpeg"
local xuri = require "xuri"


local function merge(t1, t2)
   local t = {}
   for k, v in pairs(t1) do
      t[k] = v
   end
   for k, v in pairs(t2) do
      t[k] = v
   end
   return t
end


------------------------------------------------------------------------
-- "Glob" patterns: simple patterns with "{name}" and "*" matching path
-- elements.  We transform the glob string into an LPEG pattern that returns
-- a single table containing positional and named wildcard values.
--
--    "/a/b"   --> P("/a/b")
--    "*"      --> Cg(elem)
--    "{name}" --> Cg(elem, "name")
--
------------------------------------------------------------------------

local globToLPEG
do
   local P, R, S  = lpeg.P, lpeg.R, lpeg.S
   local C, Cc, Ct, Cg, Cf = lpeg.C, lpeg.Cc, lpeg.Ct, lpeg.Cg, lpeg.Cf

   local END = P(-1)
   local elem = (P(1)-"/")^0

   local function captureName(name)
      return Cg(elem, name)
   end

   local mpName = P"{" * (R("az", "AZ", "09", "__")^1 / captureName) * "}"
   local mpSplat = P"*" / function () return Cg(elem) end
   local mpRaw = P(1) * (P(1)-S"{*")^0 / P
   local mpPath = (mpName + mpSplat + mpRaw) ^ 0
   local mpGlob = Cf( mpPath * Cc(END), function (a,b) return a*b end ) / Ct

   function globToLPEG(pat)
      return mpGlob:match(pat)
   end
end

----------------------------------------------------------------
-- Normalize response values
----------------------------------------------------------------

local function normalize(status, headers, body)
   if not status then
      print("dino.lua warning: no response values returned")
      status = 500
   end

   if type(status) ~= "number" then
      status, headers, body = 200, status, headers
   end

   if not body then
      headers, body = {}, headers
   end

   if not headers.contentType then
      headers = merge(headers, {contentType = "text/html"})
   end

   if type(body) == "table" then
      assert(headers.contentType == "text/html")
      body = htmlgen.generateDoc(body)
   end

   return status, headers, body
end

----------------------------------------------------------------
-- "Method" table = router for a particular method
--
--   local m = newMethod("GET")
--   m["/path"] = function ... end
----------------------------------------------------------------

local ROUTES = " routes "
local METHOD = " method "

local function addRoute(self, pattern, fn)
   assert(type(pattern) == "string", "dino: route pattern expected string")
   assert(type(fn) == "function", "dino: route handler expected function")

   local routes = self[ROUTES]
   local method = self[METHOD]
   local lpat -- LPEG pattern, if any

   if pattern:sub(1,1) ~= "^" then
      lpat = globToLPEG(pattern)
   end

   routes[#routes+1] = {
      method = method,
      pattern = pattern,
      lpat = lpat,
      fn = fn
   }
end

local mtMethod = {
   __newindex = addRoute,
   __call = addRoute
}

local function newMethod(routes, method)
   local me = {
      [ROUTES] = routes,
      [METHOD] = method
   }
   return setmetatable(me, mtMethod)
end


----------------------------------------------------------------
-- conditions
----------------------------------------------------------------

local function addCond(self, fnTest, fnDo)
   if type(fnTest) == "boolean" then
      local b = fnTest
      fnTest = function () return b end
   end

   assert(type(fnTest) == "function", "dino: when test expected function")
   assert(type(fnDo) == "function", "dino: when handler expected function")

   local routes = self[ROUTES]
   routes[#routes+1] = {
      condTest = fnTest,
      condDo = fnDo
   }
end

local mtCond = {
   __newindex = addCond,
   __call = addCond
}

local function newCond(routes)
   local me = {
      [ROUTES] = routes
   }
   return setmetatable(me, mtCond)
end


----------------------------------------------------------------
-- Dino class
----------------------------------------------------------------

local Dino = Object:new()

function Dino:initialize()
   self.routes = {}

   local function newm(method)
      return newMethod(self.routes, method)
   end
   self.method = memoize.newTable(newm)

   self.when = newCond(self.routes)
end


function Dino:handle(req)
   if req.query then
      local turi = xuri.parse(req.query)
      req.params = turi.params
   end

   local method, path = req.method, req.path

   assert(type(method) == "string")
   assert(type(path) == "string")

   for _, r in ipairs(self.routes) do
      if r.condTest then
         -- condition
         if r.condTest(req) then
            return r.condDo(req)
         end
      elseif r.method == method then
         -- route
         local args
         if r.lpat then
            local values = r.lpat:match(path)
            if values then
               args = { values, table.unpack(values) }
            end
         else
            local values = { string.match(path, r.pattern) }
            if values[1] then
               args = values
            end
         end
         if args then
            return r.fn(req, table.unpack(args))
         end
      end
   end
end

function Dino:__call(req)
   return normalize(self:handle(req))
end


Dino.globToLPEG = globToLPEG -- export for unit testing


return Dino
