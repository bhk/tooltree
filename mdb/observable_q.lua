local qt = require "qtest"
local O = require "observable"
local list = require "list"

local eq, assert = qt.eq, qt.assert

local Observable, Slot, Func, Log = O.Observable, O.Slot, O.Func, O.Log


--------------------------------
-- Utilities
--------------------------------


local TestSubscriber = Observable:basicNew()

function TestSubscriber:initialize()
   Observable.initialize(self)
   self.invalidations = {}
end

function TestSubscriber:invalidate(ob)
   table.insert(self.invalidations, tostring(ob))
end

function TestSubscriber:assert(obs)
   eq(self.invalidations, list.map(obs, tostring))
end

local sub1 = TestSubscriber:new()
local sub2 = TestSubscriber:new()



--------------------------------
-- Tests
--------------------------------


-- Assertion: Observable:hasInstance() detects child classes.

eq(true, Observable:hasInstance(Observable))
eq(true, Observable:hasInstance(Slot:new(1)))
eq(false, Observable:hasInstance({}))
eq(false, Observable:hasInstance(nil))

eq(true, Slot:hasInstance(Slot:new(1)))
eq(false, Slot:hasInstance(Observable))
eq(false, Slot:hasInstance({}))


-- Assertion: Slots start out "invalid" [they will not propagate invalidations
--     until after a subscriber has called `get`]

local a = Slot:new(23)
eq(a.valid, false)

-- Assertion: Slot does NOT invalidate subscribed listener when already invalid.

a:set(24)
sub1:assert{}

-- Assertion: Slot does NOT invalidate subscribed listeners when not changed.

a:subscribe(sub1)
assert(a:isSubscribed())
a:get()
a:set(24)
sub1:assert{}

-- Assertion: Slot invalidates when valid and changed

a:set(25)
sub1:assert{a}

-- Assertion: multiple subscribers are notified.

a:subscribe(sub2)
a:get()
a:set(26)
sub1:assert{a, a}
sub2:assert{a}


-- Assertion: Slot does NOT invalidate unsubscribed listener, and other
--    subscribed listeners remain subscribed.

a:unsubscribe(sub1)
a:get()
a:set(27)
sub1:assert{a, a}
sub2:assert{a, a}

a:unsubscribe(sub2)
a:get()
a:set(28)
sub2:assert{a, a}



-- Assertion: Func calculates value appropriately, getting values from
--    observable arguments and using other arguments literally.

local a = Slot:new(1)
local b = Slot:new(2)
local sub = TestSubscriber:new()

local calls = 0
local function func(a, b, c)
   calls = calls + 1
   return a * b + c
end

local f = Func:new(func, a, b, 3)

eq(f:get(), 5)
eq(calls, 1)

-- Assertion: Func subscribes to its inputs when it becomes subscribed

assert(not a:isSubscribed())
assert(not b:isSubscribed())
f:subscribe(sub)
assert(f:isSubscribed())
assert(a:isSubscribed())
assert(b:isSubscribed())

-- Assertion: When the Func is valid it does not recalculate

f:get()
calls = 0
eq(5, f:get())
eq(0, calls)

-- Assertion: When a dependency is modified, an update is triggered.

a:set(2)
eq(7, f:get())
eq(1, calls)


-- Assertion: Func unsubscribes from strict AND lazy dependencies when
-- it becomes unsubscribed.

f:unsubscribe(sub)
eq(false, f:isSubscribed())
eq(false, a:isSubscribed())
eq(false, b:isSubscribed())



-- Log

local lsub = TestSubscriber:new()

local log = Log:new()
local v1 = log:get()
eq(v1.len, 0)

log:subscribe(lsub)

log:append("a")
log:append("b")
lsub:assert{log}

local v2 = log:get()
eq(v2.len, 2)
eq(v2.a[1], "a")
eq(v2.a[2], "b")

log:clear()
lsub:assert{log, log}

log:append("c")

local v3 = log:get()
eq(v3.len, 1)
eq(v3.a[1], "c")

-- older versions intact?
eq(v1.len, 0)
eq(v2.len, 2)
eq(v2.a[1], "a")
eq(v2.a[2], "b")
