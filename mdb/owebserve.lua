-- OWebServe
--
-- owebserve.serve() constructs a web request handler for requests made by
-- clients using `oweb.js`.
--
-- Usage:
--
--   local observables = {
--      foo = observable.Slot:new()
--   }
--   dino.method.POLL["/observe"] = owebserve.serve(observables)
--
-- `Port` objects implement the POLL transaction handler.  See oweb.txt.
--


local Event = require "event"
local Object = require "object"
local thread = require "thread"
local json = require "json"
local Queue = require "queue"
local xpio = require "xpio"


local clone = require("list").clone


-- HTTP response codes for OWeb errors
local ERROR_PARSE = 400
local ERROR_CANCEL = 409
local ERROR_BADID = 410
local ERROR_INTERNAL = 500


-- Entity value for all unknown entity names
local NOT_FOUND = { error = "unk" }


local jsonHeaders = {
   contentType = "application/json"
}

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
-- Port: Each instance handles a sequence of OWeb transactions.  It
-- maintains a set of observered entites for up to two transactions: the
-- most recent response, and the most recently-acknowledged response.
--
-- When receiving an initial transaction we create a Port and call its
--`poll` method.  This subscribes to the entities named in `add`.
--
-- When we receive a successor transaction, we call the `poll` method of the
-- Port associated with its predecessor.  This may result in additional
-- subscriptions on behalf of the successor.  It may also cancel
-- subscriptions when older transactions are expired (predecessor of its
-- predecessor, or any other successsor of its predecessor).
--
----------------------------------------------------------------

local Port = Object:new()


function Port:initialize(group)
   self.group = group
   self.entries = 0     -- used by group
   self.tIdle = nil     -- used by group

   -- respXXX = most recent response
   --   ID = repsonse ID
   --   Values = name->value for every subscribed name, as of that response
   self.respID = nil
   self.respValues = {}

   -- ackXXX = most recently acknowedged response
   self.ackID = nil
   self.ackValues = {}

   -- curent subscriptions (name -> ob)
   self.subscribed = {}
   self.event = Event:new()
   self.isWaiting = false
end


function Port:discard()
   for name, ob in pairs(self.subscribed) do
      ob:unsubscribe(self)
   end
   self.subscribed = {}

   self.group:discardID(self.ackID)
   self.group:discardID(self.respID)
end


function Port:invalidate(ob)
   self.event:signal()
end


-- Return a subscribed observable, given its name.
-- Return nil if `name` is not recognized.
--
function Port:observe(name)
   local ob
   if type(name) == "string" then
      ob = self.subscribed[name]
      if not ob then
         ob = self.group.observables[name]
         if ob then
            self.subscribed[name] = ob
            ob:subscribe(self)
         end
      end
   end
   return ob
end


-- Unique value (unequal to all observed values)
local ADDED = {}


function Port:poll(req)
   if req.id == self.respID then
      -- acknowledge previous transaction
      self.group:discardID(self.ackID)
      self.ackID = req.id
      self.ackValues = self.respValues
   elseif req.id == self.ackID then
      self.group:discardID(self.respID)
   else
      return ERROR_INTERNAL
   end

   -- forget about orphaned successor, if any
   self.respID = nil
   self.respValues = {}

   -- Construct values[]:
   --   Names = set observed by this transaction
   --   Values = values as of previous transaction

   local adds = type(req.add) == "table" and req.add or {}
   local removes = type(req.remove) == "table" and req.remove or {}

   local values = clone(self.ackValues)
   for _, name in ipairs(removes) do
      values[name] = nil
   end
   for _, name in ipairs(adds) do
      if values[name] == nil then
         values[name] = ADDED
      end
   end

   -- unsubscribe from observables that are not in this set or the acked set
   for name, ob in pairs(self.subscribed) do
      if values[name] == nil and self.ackValues[name] == nil then
         ob:unsubscribe(self)
         self.subscribed[name] = nil
      end
   end

   -- wake up any other waiting threads
   while self.isWaiting do
      self.event:signal(nil, "cancel")
      thread.yield()
   end


   -- name->value for each value that differs from ackValues[]
   local changed = {}

   while true do

      -- check values
      for name, oldValue in pairs(values) do
         local value = NOT_FOUND
         local ob = self:observe(name)
         if ob then
            value = ob:get()
            if value == nil then
               value = json.null
            end
         end
         if value ~= oldValue then
            changed[name] = value
         end
      end

      if next(changed) or removes[1] then break end

      self.isWaiting = true
      local cancel = self.event:wait()
      self.isWaiting = false

      if cancel == "cancel" then
         return ERROR_CANCEL
      end
   end

   -- Update values[] to reflect values as of response time
   for name, value in pairs(changed) do
      values[name] = value
   end

   self.respID = self.group:getID(self)
   self.respValues = values

   return {
      id = self.respID,
      values = changed
   }
end



local PortGroup = Object:new()


function PortGroup:initialize(observables, lingerTime)
   self.observables = observables
   self.idToPort = {}
   self.nextID = 1
   self.linger = lingerTime or 60

   self.expireQueue = Queue:new()
end


function PortGroup:handleRequest(req)
   local id = req.id
   local port
   if id == nil then
      -- initial transaction
      port = Port:new(self)
   else
      -- successor transaction
      port = self.idToPort[id]
      if not port then
         return ERROR_BADID
      end
   end

   self.expireQueue:remove(port)
   port.entries = port.entries + 1

   local resp = port:poll(req)

   port.entries = port.entries - 1

   if port.entries == 0 then
      port.tIdle = xpio.gettime()
      self.expireQueue:put(port)
   end

   self:expire()

   return resp
end


-- Discard ports that have not been used in more than LINGER seconds.
-- Return the number of seconds until the next expiration, or nil if
-- there are no inactive ports.
--
function PortGroup:expire()
   local q = self.expireQueue
   while q:first() do
      local port = q:first()
      local t = port.tIdle + self.linger - xpio.gettime()
      if t > 0 then
         return t
      else
         q:get()
         port:discard()
      end
   end
end


function PortGroup:getID(port)
   local id = self.nextID
   self.nextID = id + 1
   self.idToPort[id] = port
   return id
end


function PortGroup:discardID(id)
   if id ~= nil then
      self.idToPort[id] = nil
   end
end


----------------------------------------------------------------
-- serve
----------------------------------------------------------------


local function serve(observables, lingerTime)
   local group = PortGroup:new(observables, lingerTime)

   local function poll(req)

      -- get and validate request body
      local reqBody = readAll(req.body)
      local req = json.decode(reqBody)
      if type(req) ~= "table" then
         return ERROR_PARSE
      end

      local resp = group:handleRequest(req)
      if type(resp) == "number" then
         return resp
      end
      return 200, jsonHeaders, json.encode(resp)
   end

   return poll
end


return {
   serve = serve,
   -- for testing
   PortGroup = PortGroup
}
