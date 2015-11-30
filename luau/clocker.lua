----------------------------------------------------------------
-- Clocker
----------------------------------------------------------------
-- Example:
--
--   clocker = require "clocker"
--   c = clocker:time(func)
--   c.time                 --> time in seconds per iteration of func()
--   c:show("title")        -- simple output
--   c:show("title", true)  -- detailed output
--
-- Or:
--
-- require("clocker"):compare{
--    function () return math.sqrt(2) end,
--    function () return math.exp(2, 0.5) end
-- }


local Clocker = {}

-- Use os.time for wall clock time.  os.clock is process CPU time, and is
-- much more accurate on linux systems, and seems appropriate for
-- comparative benchmarking purposes.
local time = os.clock

local MINTIME = 0.25

local function Measure(f)
   local t0, t1, tz
   local cnt = 0

   tz = time()
   repeat
      t0 = time()
   until t0 > tz

   tz = t0 + MINTIME
   repeat
      f() ; f() ; f() ; f() ; f()
      f() ; f() ; f() ; f() ; f()
      cnt = cnt + 10
      t1 = time()
   until t1 >= tz

   return {
      cnt = cnt,
      elapsed = t1-t0,
      time = (t1-t0)/cnt
   }
end

local Time = {}

function Time:show(name, detail)
   local prefix = ""
   if name then
      prefix = name .. ": "
   end
   io.write(string.format("%s%f us/iter\n", prefix, self.time * 1000000))
   if detail then
      io.write(string.format("   %f iterations\n   %f seconds\n   %f us/iter (raw)\n",
                             self.mRaw.cnt,
                             self.mRaw.elapsed,
                             self.mRaw.time * 1000000))
      io.write(string.format("   %f us/rep (overhead)\n   %f us/rep (adjusted)\n",
                             self.mNil.time * 1000000,
                             self.time * 1000000))
   end
end

function Clocker:init(f)
   self.mNil = Measure(f or function () end)
end

function Clocker:time(f)
   if not self.mNil then
      self:init()
   end
   local t = {}
   t.mNil = self.mNil
   t.mRaw = Measure(f)
   t.time = t.mRaw.time - t.mNil.time
   t.show = Time.show
   return t
end


-- Compare(funcs, [env])
--
-- 'funcs' is an array of functions to be timed.  Each item can be:
--     <func>
--     {<name>, <func>}
--     {name=<name>, f=<func>}
-- <func> can be a function or string (chunk contents).
--
function Clocker:compare(tbl, env)
   for ndx,t in ipairs(tbl) do
      local f, name
      if type(t) == "string" then
         f, name = t, t
      elseif type(t) == "function" then
         f, name = t, tostring(ndx)
      else
         name = t.name or t[1]
         f = t.f or t[2] or name
      end

      if type(f) == "string" then
         f = loadstring( f)
         if env then
            setfenv(f, env)
         end
      end
      local c = self:time(f)
      c:show(name)
   end
end

function Clocker:new()
   local me = { __index = self }
   return setmetatable(me, me)
end


return Clocker
