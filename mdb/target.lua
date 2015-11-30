-- A "Target" object represents the target process of a debug session.
-- It acts as a client in the debugging protocol, speaking to an mdbagent
-- instance on the other end.

local Object = require "object"
local thread = require "thread"
local xpio = require "xpio"
local BufIO = require "bufio"
local Event = require "event"
local mdbser = require "mdbser"
local futex = require "futex"
local O = require "observable"

local Target = Object:new()


-- On entry:
--   `command` is an array of words describing the command to execute.
--   `oBreak` is an observable that contains breakpoints that should be set.
--
-- On exit:
--   `target.busy` is false if all requests have been acknowledged.  Otherwise,
--        it is the time when the busy (unacknowledged) condition appeared.
--   `target.status` indicates our notion of the target's state as
--        of its last response:  new, start, pause, run, exit
--
function Target:initialize(command, oBreak)
   self.command = command
   self.oBreak = oBreak
   self.log = O.Log:new()
   self.status = O.Slot:new()
   self.busy = O.Slot:new()
   self.ovalues = setmetatable({}, { __mode = "v"})

   oBreak:subscribe(self)

   self:start()
end


function Target:start()
   -- Launch sub-process with descriptor 3 = control port
   local ctl, ctlChild = xpio.socketpair()

   local fds = { [0]=0, 1, 2, ctlChild }
   local env = xpio.env
   env.mdbFD = "3"

   self.proc = xpio.spawn(self.command, env, fds, {})
   self.ctl = BufIO:new(ctl)
   self.reader = thread.new(self.readLoop, self, self.ctl)
   self.log:append("SStarting target process")

   -- reset shared state

   self.status:set("start")
   self.pending = 0
   self.busy:set(false)
   self:send("bp", self.oBreak:get())
   for _, tv in pairs(self.ovalues) do
      if tv:isSubscribed() then
         tv:onOff(true)
      end
   end
end


function Target:shutdown()
   local proc, ctl, reader = self.proc, self.ctl, self.reader
   if not proc then
      return
   end

   self.proc, self.ctl, self.reader = nil, nil, nil

   proc:kill()
   proc:wait()

   ctl:close()

   if reader ~= xpio.getCurrentTask() then
      thread.join(reader)
   end

   self.status:set("exit")
end


function Target:readLoop(ctl)
   while true do
      local msg = ctl:read() or "exit"

      local id, body = msg:match("^([^ ]*) ?(.*)")
      if id == "ack" then
         self.pending = self.pending - 1
         if self.pending == 0 then
            self.busy:set(false)
         end
      elseif id == "exit" then
         self:shutdown()
         return
      elseif id == "log" then
         self.log:append(mdbser.decode(body))
      elseif (id == "pause" or
              id == "run")  then
         self.status:set(id)
      elseif id == "set" then
         local name, value = mdbser.decode(body)
         local ob = self.ovalues[name]
         if ob then
            ob:set(value)
         end
      else
         print("Target:readLoop: unrecognized message '" .. id .. "'")
      end
   end
end


-- Send a message to the target process.
--
function Target:send(id, ...)
   self.pending = self.pending + 1
   if self.pending == 1 then
      self.busy:set(xpio.gettime())
   end

   -- This write operation must be atomic, since multiple threads could
   -- potentially be calling this at the same time.

   if self.ctl then
      local lock = futex.lock(self.ctl)
      self.ctl:write(id .. " " .. mdbser.encode(...) .. "\n")
      futex.unlock(self.ctl)
   end
end


-- Notified by oBreak
--
function Target:invalidate(ob)
   self:send("bp", ob:get())
end


--------------------------------
-- TargetValue: observes target property
--------------------------------


local TargetValue = O.Slot:basicNew()


function TargetValue:initialize(target, name)
   O.Slot.initialize(self)
   self.name = name
   self.target = target
end


function TargetValue:onOff(isOn)
   if isOn then
      self.target:send("sub", self.name)
   else
      self.target:send("unsub", self.name)
   end
end


----------------------------------------------------------------
-- Public methods
----------------------------------------------------------------


-- limit = "over" | "in" | "out" | nil
--
function Target:run(limit)
   self:send("run", limit)
end


function Target:pause()
   self:send("pause")
end


function Target:observe(name)
   local tv = self.ovalues[name]
   if not tv then
      tv = TargetValue:new(self, name)
      self.ovalues[name] = tv
   end
   return tv
end


function Target:eval(command)
   self:send("eval", command)
end


function Target:restart()
   self:shutdown()
   self:start()
end


function Target:close()
   self:shutdown()
   self.oBreak:unsubscribe(self)
end


return Target
