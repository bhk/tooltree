local qt = require "qtest"
local observable = require "observable"
local thread = require "thread"
local owebserve = require "owebserve"
local ValueMap = require "valuemap"
local Object = require "object"
local xpio = require "xpio"

local eq = qt.eq


local function shallow(value)
   if type(value) ~= "table" then
      return value
   end
   local t = {}
   for k, v in pairs(value) do
      t[type(k) == "table" and tostring(k) or k] =
         type(v) == "table" and tostring(v) or v
   end
   return t
end


local function eqShallow(a,b)
   qt._eq(shallow(a), shallow(b))
end


local checkItems = owebserve.checkItems


local function test1()
   local vm = ValueMap:new(5)

   local entities = {
      foo = observable.Slot:new(9),
      bar = observable.Slot:new(8)
   }
   local items = {
      {"foo", ""},
      {"bar", ""}
   }

   local function updateVersions(items)
      local newItems = {}
      for ndx, item in ipairs(items) do
         newItems[ndx] = { item[1], vm:toID(entities[item[1]]:get()) }
      end
      return newItems
   end

   -- all fresh (version == "")

   local fresh, stale = checkItems(vm, entities, items)
   local newItems = updateVersions(items)
   eq(fresh, { {"foo", "", newItems[1][2], 9},
               {"bar", "", newItems[2][2], 8} });
   eq(stale, {})

   -- all stale

   items = newItems
   local fresh, stale = checkItems(vm, entities, items)
   eq(fresh, {})
   eq(stale[entities.foo], true)
   eq(stale[entities.bar], true)

   -- outdated value (change to observable -> new version)

   entities.foo:set(99)
   local fresh, stale = checkItems(vm, entities, items)
   newItems = updateVersions(items)

   eq(fresh, { {"foo", items[1][2], newItems[1][2], 99} })
   eq(stale[entities.bar], true)

end

--------------------------------

local MockEvent = Object:new()

function MockEvent:initialize()
   self.signaled = 0
end

function MockEvent:signal()
   self.signaled = self.signaled + 1
end

function MockEvent:wait()
   if self.onWait then
      self.onWait()
   end
end

--------------------------------

local MockSlot = Object:new()

function MockSlot:initialize(value)
   self.value = value
end

function MockSlot.subscribe (self, fn)
   self.fn = fn
   self.isSubscribed = true
end

function MockSlot.unsubscribe (self, fn)
   assert(fn == self.fn)
   self.fn = nil
   self.isSubscribed = false
end

function MockSlot.notify (self)
   if self.fn then
      self.fn(self)
   end
end


--------------------------------

local function test2()
   local a = MockSlot:new(1)
   local b = MockSlot:new(2)

   function MockEvent.onWait()
      a:notify()
      b:notify()
   end


   local wait, flush = owebserve.newLingerPool(0, MockEvent)

   local pollSet = { [a] = true, [b] = true }
   wait(pollSet)
   eq(a.isSubscribed, true)
   eq(b.isSubscribed, true)

   -- expire b

   local t0 = xpio.gettime()
   while t0 == xpio.gettime() do end
   wait({[a] = true})
   eq(a.isSubscribed, true)
   eq(b.isSubscribed, false)

   -- flush
   flush()
   eq(a.isSubscribed, false)
   eq(b.isSubscribed, false)

end


local function isSubscribed(ob)
   return next(ob.subscribers) and true or false
end

local PortGroup = owebserve.PortGroup

local omap = {
   foo = observable.Slot:new(9),
   bar = observable.Slot:new(8)
}


local function testPoll()
   local grp = PortGroup:new(omap)

   -- Assertion: initial request constructs port, registers ID, subscribes
   --    to entities, and reponds immediately (known entity).

   local resp = grp:handleRequest({add = {"foo"}})
   eq(resp, { id=1, values={foo=9} })
   local id1 = resp.id
   local port1 = grp.idToPort[id1]

   assert(id1)
   assert(port1)
   eq(resp.values, { foo = 9 })
   eq(omap.foo:isSubscribed(), true)

   do
      -- Assertion: another initial request creates a different port.
      -- Assertion: unknown entities are assigned ERROR_ENTITY

      local respErr = grp:handleRequest({add = {"abc", "def"}})
      local eid1 = respErr.id
      local eport = grp.idToPort[eid1]
      assert(eport)
      assert(grp.idToPort[respErr.id])
      assert(grp.idToPort[respErr.id] ~= port1)
      eq(respErr.values, { abc = {error="unk"},
                           def = {error="unk"} })

      -- Assertion: A transaction removing an item completes immediately.

      respErr = grp:handleRequest({id = eid1, remove={"def"}})
      assert(respErr.id)
      eq(respErr.values, {})
      eq(eport.respValues, { abc = {error="unk"} })
   end

   -- Assertion: successor response registers same Port with second reponse ID.

   resp = grp:handleRequest({id = id1, add = {"bar"}, remove = {"foo"}})
   local id2 = resp.id
   assert(id2)
   assert(id2 ~= id1)
   eq(grp.idToPort[id1], port1)
   eq(grp.idToPort[id2], port1)
   eq(resp.values, { bar = 8 })

   eq(omap.foo:isSubscribed(), true)
   eq(omap.bar:isSubscribed(), true)

   eq(port1.ackValues, {foo=9})
   eq(port1.respValues, {bar=8})

   -- Assertion: predecessor of predecessor is discarded (foo unsubscribed).
   -- Assertion: response is immediate when value of watched entity has
   --    changed since last response.
   -- Assertion: Entity is unsubscribed when the last transaction watching
   --    it is discarded.

   omap.bar:set(1)
   resp = grp:handleRequest({id = id2})
   local id3 = resp.id
   assert(id3)
   assert(id3 ~= id2)
   eq(grp.idToPort[id3], port1)
   eq(grp.idToPort[id2], port1)
   eq(grp.idToPort[id1], nil)

   eq(resp.values, { bar = 1 })

   eq(omap.foo:isSubscribed(), false)
   eq(omap.bar:isSubscribed(), true)

   eq(port1.ackValues, {bar=8})
   eq(port1.respValues, {bar=1})


   -- Assertion: add AND remove of same entity => entity is ready

   resp = grp:handleRequest({id=id3, remove={"bar"}, add={"bar"}})
   local id4 = resp.id
   eq(resp.values, { bar = 1 })
   eq(grp.idToPort[id2], nil)

   eq(port1.ackValues, {bar=1})
   eq(port1.respValues, {bar=1})


   -- Assertion: different successor of ackID discards other successor

   resp = grp:handleRequest({id=id3, remove={"bar"}, add={"foo"}})
   assert(resp.id ~= id4)
   eq(grp.idToPort[id4], nil)

   id4 = resp.id

   eq(resp.values, { foo = 9 })
   eq(grp.idToPort[id2], nil)

   eq(omap.foo:isSubscribed(), true)
   eq(omap.bar:isSubscribed(), true)

   eq(port1.ackValues, {bar=1})
   eq(port1.respValues, {foo=9})


   -- Assertion: no additions => pause until an entity changes.

   local runCount = 0
   thread.new(function ()
                 for n = 1, 9 do
                    thread.yield()
                    runCount = runCount + 1
                 end
                 omap.foo:set(10)
              end)

   resp = grp:handleRequest({id=id4})

   eq(runCount, 9)

   local id5 = resp.id
   eq(grp.idToPort[id5], port1)
   eq(resp.values, { foo = 10 })
   eq(grp.idToPort[id2], nil)

   eq(omap.foo:isSubscribed(), true)
   eq(omap.bar:isSubscribed(), false)

   eq(port1.ackValues, {foo=9})


   -- Assertion: pre-empted transaction returns error, while pre-empting
   -- transaction succeeds.

   runCount = 0
   local otherResp
   thread.new(function ()
                 for n = 1, 9 do
                    thread.yield()
                    runCount = runCount + 1
                 end
                 otherResp = grp:handleRequest({id=id5})
              end)

   local resp = grp:handleRequest({id=id5})
   eq(resp, 409)
   eq(otherResp, nil)
   omap.foo:set(2)
   thread.yield()
   thread.yield()
   eq(otherResp.values, {foo=2})

   local id6 = otherResp.id
   eq(grp.idToPort[id5], port1)
   eq(grp.idToPort[id6], port1)

   -- Assertion: after `linger` time, port is discarded.

   grp.linger = 0
   grp:expire()
   eq(grp.idToPort[id5], nil)
   eq(grp.idToPort[id6], nil)
   eq(omap.foo:isSubscribed(), false)
end


local function constStream(data)
   local me = {}
   local pos = 1
   function me:read(amt)
      eq(type(amt), "number")
      local o = data:sub(pos, pos + amt - 1)
      pos = pos + #o
      return o ~= "" and o or nil
   end
   return me
end


local function testServe()
   local poll = owebserve.serve(omap)

   local a, b, c = poll {
      body = constStream '{"add":["A"]}'
   }

   eq(a, 200)
end

--------------------------------
-- main
--------------------------------

local done = false

local function main()
   testPoll()
   testServe()
   done = true
end

thread.dispatch(main)
assert(done)
