-- Stubbed out implementations of `thread` and `xpio` libraries that allow
-- for running threads that sleep, while the controlling test code can
-- control time.

--------------------------------
-- xpio.gettime()
-- xpio.getCurrentThread()
-- xpio.setCurrentThread()
--
-- xpio.settime() -- for testing
--------------------------------

local xpio = {}

xpio._now = 1


function xpio.gettime()
   return xpio._now
end


function xpio.settime(t)
   xpio._now = t
end


function xpio.getCurrentThread()
   return xpio.currentThread
end


function xpio.setCurrentThread(thread)
   xpio.currentThread = thread
end


--------------------------------
-- thread.new
-- thread.sleep
-- thread.sleepUntil
-- thread.yield
-- thread.kill
--
-- thread.settle()      -- for testing
-- thread.queryState()  -- for testing
--------------------------------

-- array of runnable coroutines
local ready = setmetatable({}, { __index = table })
local run = setmetatable({}, { __index = table })

-- array of {t=readyTime, c=coroutine} records
local sleepers = setmetatable({}, { __index = table })


local thread = {}

function thread.new(fn, ...)
   local args = table.pack(...)
   local function preamble()
      local succ, err = xpcall(fn, debug.traceback, table.unpack(args))
      if not succ then
         error(err, 0)
      end
   end
   local t = coroutine.create(preamble)
   ready:insert(t)
   return t
end


function thread.yield()
   local thread = coroutine.running()
   ready:insert(thread)
   coroutine.yield()
end


function thread.sleepUntil(t)
   sleepers:insert {
      t = t,
      c = coroutine.running()
   }
   coroutine.yield()
end


function thread.sleep(duration)
   return thread.sleepUntil(duration + xpio.gettime())
end


function thread.kill(thread)
   for ndx, cr in ipairs(ready) do
      if cr == thread then
         ready:remove(ndx)
         return
      end
   end

   for ndx, s in ipairs(sleepers) do
      if s.c == thread then
         sleepers:remove(ndx)
         return
      end
   end

   error("thread.kill: could not find thread " .. tostring(thread))
end


function thread.dispatch(...)
   thread.new(...)

   repeat

      run, ready = ready, run

      while run[1] do
         local cr = run:remove(1)
         xpio.setCurrentThread(cr)
         local succ, err = coroutine.resume(cr)
         if not succ then
            error("Error in thread:\n" .. err, 0)
         end
         xpio.setCurrentThread(nil)
      end

      -- wake sleepers
      local ndx = 1
      while ndx <= #sleepers do
         local s = sleepers[ndx]
         if s.t <= xpio.gettime() then
            ready:insert(s.c)
            sleepers:remove(ndx)
         else
            ndx = ndx + 1
         end
      end

   until not ready[1]

   assert(not sleepers[1],  "leaked a thread waiting on time")
end


-- Keep yielding the current thread until all other threads are done (exited
-- or scheduled on future timer expiration).
--
function thread.settle()
   repeat
      while #run + #ready > 0 do
         thread.yield()
      end

      if sleepers[1] then
         thread.yield()
      end

   until #ready + #run == 0
end


-- Returns nTimers, nReady
--   nTimers = number of threads currently sleeping
--   nReady = number of threads in run or ready queue (this will not
--            include the calling thread)
--
function thread.queryState()
   return #sleepers, #run + #ready
end


-- Install `xpio` and `thread` in package.loaded so subsequently loaded
-- packages will use these implementations.
--
local function install()
   package.loaded.xpio = xpio
   package.loaded.thread = thread
end


return {
   xpio = xpio,
   thread = thread,
   install = install
}
