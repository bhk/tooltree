-- agentlib_q.lua

local qt = require "qtest"
local xpio = require "xpio"

------------------------------------------------------------------------
-- Construct test environment for agentlib

local clientPort, agentPort = xpio.socketpair()

local env = xpio.env
env["mdbFD"] = tostring(agentPort:fileno())

function os.getenv(name)
   return env[name]
end

_G.arg = nil

local mtQ = getmetatable(xpio.tqueue())
local _wait = mtQ.wait

------------------------------------------------------------------------

local agentlib = require "agentlib"


local eq = qt.eq


--------------------------------
-- xformat
--------------------------------

local xformat = agentlib.xformat

local formatFuncs = {
   Q = function (f, v) return "{Q:" .. v .. "}" end,
   s = function (f, v) return "{s:" .. v .. "}" end,
   default = string.format
}

local function ff(...)
   return table.concat(xformat(formatFuncs, ...))
end

eq("{s:abc}", ff("abc"))

-- Defaults to string.format if not provided in formatFuncs
eq("{s:abc}001", ff("abc%03d", 1))

-- Uses "%s" on format text
eq("{s:abc}{s:def}", ff("abc%s", "def"))

eq("{s:abc}{Q:def}", ff("abc%Q", "def"))


--------------------------------
-- Activate debugging, but send "run" command
--------------------------------

clientPort:write("run\n")

agentlib.start()


-- tq:wait() is interruptible

debug.sethook()

local a, b = xpio.socketpair()

local count = 0
local function hook(err, line)
   count = count + 1
   if count == 100 then
      a:try_write("x")
   end
end

local tq = xpio.tqueue()
local task = { _queue = tq }

-- Make agentPort readable, so hook will be called repeatedly
clientPort:write("run\n")

-- Wait on 1 second timeout (hook should be called enough to write to `a`)

b:when_read(task)

debug.sethook(hook, "l")
local ready = tq:wait(1)
debug.sethook()

eq(ready, {task})
eq("x", b:read(10))


-- Wait on nil timeout (will wait forever if hook is not called)

b:when_read(task)
count = 0
debug.sethook(hook, "l")
ready = tq:wait()
debug.sethook()

eq(ready, {task})
