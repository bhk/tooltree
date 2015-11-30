local qt = require "qtest"
local popen = require "popen"
local thread = require "thread"


local eq = qt.eq


local function main()

   -- Read from a popen'ed process

   local f = popen({"ls"})
   local text = f:read("*a")

   qt.match(text, "popen_q.lua\r?\n")
   qt.match(text, "\n$")

   local code = f:close()
   eq(code, 0)
   eq(f.proc, nil)


   -- Write to a popen'ed process

   local f = popen({"grep", "ok"}, "w")
   eq(1, f:close())  -- not found

   local f = popen({"grep", "ok"}, "w")
   f:write("abc\nok\ndef\n")
   eq(0, f:close())  -- found
end

thread.dispatch(main)
