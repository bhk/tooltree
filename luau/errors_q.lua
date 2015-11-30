local qt = require "qtest"
local errors = require "errors"
local catch = errors.catch

local E = qt.eq

----------------------------------------------------------------
-- Implementation Notes
--
-- In order to provide traceback information for uncaught errors, we must
-- construct traceback strings in the errhandler.
--
-- The standard Lua interpreter uses a top-level error handler that
-- concatenates a traceback onto the error message.  This string gets
-- returned from lua_pcall and the interpreter's 'report' function then
-- prints that string out.  When a user passes and error message of type
-- table, first the error handler decides not to append a traceback, and
-- then the report function prints "(error object is not a string)".  The
-- __tostring metamethod does not help here since neither the error handler
-- nor report() will recognize it.  This rules out using non-string error
-- messages if we want to work nicely with the standalone interpreter's
-- handling of uncaught errors.
--
-- We encode our exception in the string passed to error():
--
--    throw("msg")
--    -> error("msg")
--      -> errorhandler("file:line: msg")   : concatenates trace
--        ->  "file:line: msg\n<trace>"
--
----------------------------------------------------------------

local function f(a,b)
   if (a == b) then
      error("equal")
   elseif a > b then
      error("greater\n" .. a .. ">" .. b)
   end
   return "ok"
end

local function g(...)
   local e, r = catch("greater\n(.*)", f, ...)
   if e then
      return e.values[1]
   end
   return r
end


-- Simple case
--
function qt.tests.f()
   local succ, e, r

   E("ok", f(1,2))

   e,r = catch("equal", f, 1, 2)
   E(e, false)
   E(r, "ok")

   e,r = catch("eq(.*)", f, 1, 1)
   E("equal", e.message)
   E({"ual"}, e.values)

   e,r = catch("lt,equal,nothappen", f, 1, 1)
   E("equal", e.message)
   E({"equal"}, e.values)

   e,r = catch("greater\n(.*)", f, 2, 1)
   E("greater\n2>1", e.message)
   E({"2>1"}, e.values)

   succ,r = pcall(catch, "eq(.*)", f, 2, 1)
   E(false, succ)
   E("greater", string.match(r, ".-:.-: ([^\n]*)\n.-\nstack traceback"))
end


-- two levels of nesting
--
function qt.tests.g()
   local succ, e, r

   E("ok", g(1,2))

   e,r = catch("equal", g, 1, 2)
   E(e, false)
   E(r, "ok")

   e,r = catch("eq(.*)", g, 1, 1)
   E("equal", e.message)
   E({"ual"}, e.values)

   e,r = catch({"xxx", "eq(.*)"}, g, 1, 1)
   E("equal", e.message)
   E({"ual"}, e.values)

   succ,r = pcall(catch, {"^equal $"}, g, 1, 1)
   E(false, succ)  -- not caught by catch()
   E("equal", e.message)
   E("equal", string.match(r, ".-:.-: ([^\n]*)\nstack traceback"))

   r = g(2, 1)
   E("2>1", r)

   e,r = catch("eq(.*)", g, 2, 1)
   E(false, e)  -- not an exception
   E("2>1", r)
end


-- argument & return value preservation
function qt.tests.echo()
   local function echo(...)
      return ...
   end

   qt.eq(table.pack(catch("", echo, 1, nil)),  {n=3, false, 1})
end


return qt.runTests()
