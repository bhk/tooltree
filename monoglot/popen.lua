-- popen() is much like io.popen() except for:
--
--   * it blocks only the calling thread (corouting), not the entire process
--   * the command is given as an array of words, not as a string

local xpio = require "xpio"
local BufIO = require "bufio"


local POpen = BufIO:basicNew()


function POpen:initialize(command, mode)
   local stdin = 0
   local stdout = 1
   local openedFile

   local r, w = xpio.pipe()

   if mode == "w" then
      stdin, openedFile = r, w
   else
      openedFile, stdout = r, w
   end

   BufIO.initialize(self, openedFile)

   self.proc = xpio.spawn(command, xpio.env, {[0] = stdin, [1] = stdout, [2] = 2})
end


function POpen:close()
   BufIO.close(self)

   local proc = self.proc
   self.proc = nil

   local reason, code = proc:wait()
   return reason == "signal" and code*256 or code
end


function POpen:__gc()
   if self.proc then
      self.proc:kill()
   end
end


local function popen(command, mode)
   return POpen:new(command, mode)
end


return popen
