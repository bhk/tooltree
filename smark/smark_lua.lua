-- smark "lua" macro
--
-- See the smark user guide for documentation on the lua macro's interface.
--
-- This implementation ensures that errors and backtraces that result from
-- embedded Lua code will be fixed up to point into the original document,
-- so an editor or IDE's "next error" function will position the cursor at
-- the appropriate place.

local smarklib = require "smarklib"
local smarkmisc = require "smarkmisc"

local lineToPos = smarkmisc.lineToPos

----------------------------------------------------------------
-- loadstringwith
----------------------------------------------------------------

-- loadstring with lexically scoped variables (pre-defined upvalues)
--
--  str : same as in loadstring() (chunk to be compiled)
--  name : same as in loadstring()
--  locals : variables to manifest as locals in the compiled chunk
--  globals : table to be set as the environment for the function
--
local function loadstringwith(str, name, locals, globals)
   assert(type(str) == "string")
   local f, err
   if not locals or next(locals) == nil then
      f, err = load(str, name, nil, globals)
   else
      local names, values = {}, {}
      for k,v in pairs(locals) do
         table.insert(names, k)
         table.insert(values, v)
      end
      local c = string.format("local %s=... return function () %s\nend",
                              table.concat(names, ","), str)
      f, err = load(c, name or str, nil, globals)
      if f then
         f = f(table.unpack(values))
      end
   end
   return f, err
end

----------------------------------------------------------------
-- Rewriting backtraces and load errors
----------------------------------------------------------------

-- locator = locators[integer]
-- fileName, lineNumber, columnNumber = locator(lineNumber)

local locators = {}

local _pcall = pcall

local function embeddedErrLocation(nstr, nline)
   local locator = locators[tonumber(nstr)]
   if locator then
      local file, line, col = locator(nline)
      return (file or "??") ..":" .. (line or "??") .. ":" ..
             (tonumber(col) and col..":" or "")
   end
end


-- Re-write error message line indicators from:
--    .lua<NN>:<lnum>: ...
-- to:
--    <file>:<lnum>:<column>: ...
--
-- for the embedded location.

local function embeddedFixError(err)
   if type(err) == "string" then
      err = err:gsub("%.lua!(%d):(%d+):", embeddedErrLocation)
   end
   return err
end


-- embedded_pcall: User-provided functions should be called via
-- embedded_pcall(), which will pcall() and rewrite any error messages for
-- embedded functions on the stack trace.  The caller should in the meantime
-- be prepared to continue processing, following the Smark principle of
-- "warn, don't fail".

local function embedded_pcall(fn, ...)
   local succ, result = _pcall(fn, ...)
   if not succ then
      return succ, embeddedFixError(result)
   end
   return succ, result
end


-- monkey-patch 'pcall' (shame, shame) so every caller will inherit
-- embeddedFixError functionality.

pcall = embedded_pcall


-- Load a chunk of Lua that has been embedded within a document.  This will
-- allow error backtraces to be fixed up (with embeddedFixError) to point
-- directly into the embedded location.

local function loadsourcedlua(str, locator, locals, globals)
   table.insert(locators, locator)
   local f, msg = loadstringwith(str, "@.lua!"..(#locators), locals, globals)
   if not f then
      msg = embeddedFixError(msg)
   end
   return f, msg
end


local function luaMacro(node, doc)
   local source = node._source
   local text = node.text

   -- Construct environment for embedded lua
   local locals = {
      doc = doc,
      source = source
   }
   for k,v in pairs(smarklib) do
      locals[k] = v
   end

   if not text:match("\n") then
      -- inline lua macros have implicit return. E.g.:  \lua{1+2}
      text = "return " .. text
   end

   local function locator(line)
      local pos = lineToPos(text, tonumber(line))
      local fsrc, pos, line, col = source:where(pos)
      return fsrc.fileName, line, col
   end

   local f, msg = loadsourcedlua(text, locator, locals, _G)
   if not f then
      source:warn(nil, ".lua macro compilation\n%s\n", msg)
   else
      local succ, result = embedded_pcall(f)
      if succ then
         return result
      end
      source:warn(nil, ".lua macro execution\n%s\n", result)
   end
end

return luaMacro
