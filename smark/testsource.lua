local qt = require "qtest"
local Source = require "source"


-- TestSource captures errors in the originating source.

local function newSource(str)
   str = str:gsub("\r", "")

   local source = Source:newFile("TEST", str)
   local errors = {}
   source.errors = errors

   function source:printError(message, source, pos, line, col)
      table.insert(errors, {message, pos})
   end

   return source
end


-- dmatch(a, b) => match( describe(a), describe(b) )
--
local function dmatch(str, pattern, lvl)
   str, pattern = qt.describe(str), qt.describe(pattern)
   if not str:match(pattern) then
      qt.error(qt.format("\nExpected: %Q\n      in: %Q\n", pattern, str), (lvl or 1) + 1)
   end
end


return {
   new = newSource,
   dmatch = dmatch
}
