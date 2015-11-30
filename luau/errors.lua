-- errors.lua
--
-- Catch expected errors (for graceful handling) but re-throw *unexpected*
-- errors (for traceback dumps).
--
--    errors.catch(pats, func, [args])  ->  e, [values]
--
-- Catch will call 'func' passing it all of [args].  If the call succeeds,
-- catch will return false followed by func's return values.
--
-- 'pats' describes the expected errors.  It may be a table of pattern
-- strings or a string of comma-delimited patterns.  All patterns are rooted
-- ("^" will be prefixed to them).
--
-- If an error terminates the call to 'func', and the error message does not
-- match any pattern in pats, then it will be "re-thrown" to be handled by
-- the next enclosing catch/pcall/xpcall.  if the error message does match
-- a pattern in pats, then catch() will return a table with the following
-- fields:
--
--    err.message = the error message (as passed to error())
--    err.values  = captures from the first matching pattern
--    err:reThrow() = a method that will re-throw the error with the
--          original stack trace (if unhandled, this will be displayed by
--          the interpreter)
--
-- catch() is optimized for the case involving successul invocation with no
-- errors.
--
-- Example:
--
--   e,r = catch("myerror (.*)", f, "x")
--   if e then
--      return nil, e.values
--   end
--   return r
----------------------------------------------------------------

local debug = require "debug"

-- Avoid constructing a new closure every time catch is called
local function catch(pats, func, ...)
   local r = table.pack( xpcall(func, debug.traceback, ...) )
   local succ = r[1]
   if succ then
      return false, table.unpack(r, 2, r.n)
   end

   if type(pats) == "string" then
      local t = {}
      for p in pats:gmatch("([^,]+),?") do
         table.insert(t, p)
      end
      pats = t
   end
   local e = r[2]
   local m = e:match("(.-)\nstack traceback:\n") or e
   m = m:match("^.-:%d+: (.*)") or m

   for _,p in ipairs(pats) do
      local v = { m:match("^"..p) }
      if v[1] then
         return {
            errstr = e,
            message = m,
            values = v,
            reThrow = function(self) error(self.errstr, 0) end
         }
      end
   end

   -- rethrow
   error(e, 0)
end

return {
   catch = catch,
}
