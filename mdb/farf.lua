--local qt = require "qtest"
local dbgFlags = os.getenv("FARF") or ""

local function farf(pattern, fmt, ...)
   if dbgFlags:match(pattern) then
      if fmt then
         io.stderr:write(string.format(fmt.. "\n", ...))
      end
      return true
   end
end

local function nada()
end

return dbgFlags=="" and nada or farf
