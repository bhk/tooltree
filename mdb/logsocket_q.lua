local qt = require "qtest"
local logsocket = require "logsocket"
local Object = require "object"

local eq = qt.eq

local lines = {}
local function writeLine(line)
   lines[#lines+1] = line
end


--------------------------------
-- escape
--------------------------------

eq("a\\001\n\\255\\000x",
   logsocket.escape("a\1\n\255\0x"))


--------------------------------
-- logResults
--------------------------------

local logger = {
   _num = 1,
   _writeLine = writeLine,
   _log = logsocket._log
}


logger:_log("read", "a\1\2\nb")
eq(lines, { [[[1]read: a\001\002]],
            [[[1]read: b\]] })


lines = {}
logger:_log(
   "read",
   ".........|.........|.........|.........|.........|.........|.........|.........|.........|")

eq(lines, {
      [[[1]read: .........|.........|.........|.........|.........|.........|.........|.........|\]],
      [[[1]read: .........|\]] })


--------------------------------
-- wrap
--------------------------------

local TestSocket = Object:new()

function TestSocket:initialize()
   self.calls = setmetatable({}, { __index = table})
end

function TestSocket:read(n)
   self.calls:insert( "read:" .. n )
   return nil, "retry"
end

function TestSocket:write(data)
   self.calls:insert( "write:" .. data )
   return nil, "retry"
end

function TestSocket:close(n)
   self.calls:insert( "close" )
   return true
end

function TestSocket:shutdown(n)
   self.calls:insert( "shutdown" )
   return true
end

function TestSocket:accept(bSucceed)
   if bSucceed then
      return TestSocket:new()
   end
   return nil, "ERROR"
end


local wrap = logsocket.wrap

local ts = TestSocket:new()
local ws = wrap(ts, writeLine)

-- Assertion: Undefined in inner => undefined in outer.

eq(nil, ws.notdefined)


-- Assertion:  Method calls are forwarded to the inner socket.

eq({nil, "retry"}, {ws:read(12)})
eq({nil, "retry"}, {ws:write("foo")})
eq({true}, {ws:close()})
eq({true}, {ws:shutdown()})

eq(ts.calls, { "read:12",
               "write:foo",
               "close",
               "shutdown" })

-- Assertion:  Socket returned by "accept" is automatically wrapped

eq({nil, "ERROR"}, {ws:accept()})
local ws2 = ws:accept(true)
eq({true}, {ws2:close()})
eq(ws2.inner.calls, {"close"})
