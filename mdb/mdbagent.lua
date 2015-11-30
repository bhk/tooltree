-- mdbagent.lua: Target-side debug protocol endpoint
--
-- mdbagent can be used two ways:
--    1. lua -l mdbagent <targetprogram>
--    2. lua mdbagent.lua <targetprogram>
--
-- In the first case, we expect the target code to execute after mdbagent.
-- In the second case, mdbagent loads and calls the target program. This
-- allows mdbagent to trap uncaught errors before the program terminates.

local isDebugging = tonumber(os.getenv("mdbFD"))

if arg then
   -- load and call target program
   local main
   local err = "no source file provided"

   if arg[1] then
      main, err = loadfile(arg[1])
   end
   if err then
      print("mdbagent: " .. err)
      return 1
   end

   -- shift arguments down by one (erasing mdbagent.lua)
   for ndx = 0, #arg do
      arg[ndx] = arg[ndx+1]
   end

   if not isDebugging then
      return main(...)
   end

   -- copy these before agentlib replaces them with instrumented versions
   local exit, xpcall = os.exit, xpcall

   local agent = require "agentlib"
   agent.start()

   local ok, err = xpcall(main, agent.mainHandler, ...)
   if not ok then
      io.stderr:write("lua: " .. tostring(err) .. "\n")
      exit(1)
   end
   return ok

else
   -- invoked using `-l mdbagent`

   if isDebugging then
      require("agentlib").start()
   end
end
