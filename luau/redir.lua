-- redir.lua:  Redirect stdin, stdout, stderr, and exit().
--
-- This module enables redirection of Lua I/O similarly to how ">" or "|"
-- would redirect an executable's output.
--
-- redir:hook() replaces Lua's default I/O functions with versions that
-- route *through* io.stdin, io.stdout, and io.stderr, so assigning
-- io.stdout will redirect output.  Hook also replaces os.exit with a
-- function that delegates to redir.exit.  This should be called early,
-- before the modules under test get an opportunity to acquire references to
-- the original definitions.
--
-- redir:pcall() executes a function in a context that harnesses its I/O and
-- captures any calls to os.exit().  (Redirection of I/O should generally be
-- done only within a pcall context, since an error would then result in
-- mysterious results.)
--
-- Note: Redefining globals at run time is messy.  Unless Hook() is called
--   before anything else executes, other modules could have their own
--   references to the original definitions.  Also, we would ultimately want
--   to control the scope of the redefinition.  pcall() scopes the
--   redirection in time (turning it on before calling the function and off
--   on return) which is not ideal.  Creating a new global table with an
--   alternative 'require' implementation -- a new 'env' or class loader --
--   would be much better.
--
-- Note: io.{stdin,stdout,stderr} are not replaced by hook(); it is assumed
--   the client of redir controls these.  If this is not done similarly
--   early, modules under test might obtain references to the original
--   values.
--
local redir = {}

local debug = require "debug"

-- save original values
redir._stdin = io.stdin
redir._stdout = io.stdout
redir._stderr = io.stderr
redir._write = io.write
redir._read = io.read
redir._type = io.type
redir._print = print
redir._exit = os.exit
redir._getenv = os.getenv

-- currently active forms, for the traps
redir.exit   = os.exit
redir.getenv = os.getenv

local function trap_io_write(...)
   return io.stdout:write(...)
end

local function trap_io_read(...)
   return io.stdin:read(...)
end

local function trap_io_type(f)
   if type(f) == "table" and f.redir == redir then
      return f:type()
   end
   return redir._type(f)
end

local function trap_getenv(...)
   return redir.getenv(...)
end

local function trap_print(...)
   local args = {}
   for n = 1,select('#',...) do
      table.insert(args,tostring(select(n,...)))
   end
   io.stdout:write(table.concat(args,"\t").."\n")
end

local function trap_exit(...)
   return redir.exit(...)
end

local errorExitCode = 0
local function errorExit(n)
   errorExitCode = tonumber(n)
   assert(errorExitCode)
   error("<<errorExit>>", 0)
   redir._exit(n)
end

local TrapFile = {}
TrapFile.__index = TrapFile

function TrapFile:read(...)  return self.f:read(...) end
function TrapFile:write(...) return self.f:write(...) end
function TrapFile:close(...) return self.f:close(...) end
function TrapFile:type(...)  return self.f:type(...) end
function TrapFile:flush(...) return self.f:flush(...) end

local function newTrapFile(f)
   return setmetatable( { f=f, redir=redir}, TrapFile )
end

-- Override global functions that provide alternate paths to stdin/stdout.
-- Hook() should be called early on (before other libraries have a chance to
-- make copies of the original unhooked definitions).
--
function redir:hook()

   for _,f in ipairs{"stdin", "stdout", "stderr"} do
      io[f] = newTrapFile(io[f])
   end

   io.write = trap_io_write
   io.read = trap_io_read
   io.type = trap_io_type
   print = trap_print
   os.getenv = trap_getenv
   os.exit = trap_exit
end

--------------------------------
-- RedirFile class
--------------------------------

local RedirFile = {}
RedirFile.__index = RedirFile

function RedirFile:write(s)
   if self.tee then self.tee:write(s) end
   table.insert(self.wdata, s)
   return #s
end

function RedirFile:read(amt)
   local d, rest = self.rdata, ""
   if amt == "*l" or amt == nil then
      d, rest = d:match("(.-)\r?\n(.*)")
      if not d then
         d, rest = self.rdata, ""
      end
   elseif amt == "*a" then
      -- nothing
   elseif type(amt) == "number" then
      d, rest = d:sub(1,amt), d:sub(amt+1)
   else
      error("RedirFile:1: bad argument #1 ("..tostring(amt)..", type "..type(amt)..") to 'read' (invalid option)")
   end
   if self.rdata == "" and amt ~= "*a" then
      return nil
   end
   self.rdata = rest
   return d
end

function RedirFile:close()
   self.type = function () return "closed file" end
end

function RedirFile:_getdata()
   return table.concat(self.wdata)
end

function RedirFile:flush()
end

local function newRedirFile(file, tee)
   local me = {
      rdata = type(file) == "string" and file or "",
      wdata = type(file) == "table" and file or {},
      tee = tee,
      type = function () return "file" end,
      redir = redir,
   }
   return setmetatable(me, RedirFile)
end


-- pcall: Call a function with I/O and os.exit() harnessed.  stdin, if
-- redirected, may be specified as a string.  stdout and stderr, if
-- redirected, are specified as tables into which strings will be inserted.
--
-- On entry:
--   cxt.stdin   = string  (nil to use current stdin)
--   cxt.stdout  = table   (nil to use current stdout)
--   cxt.stderr  = table   (nil to use current stderr)
--   cxt.environ = table   (nil to use current OS environment)
--   cxt.tee     = if true, tee captured output to original file
--
-- On exit:
--    nil, errorstring    (on error)
--    true, ...values...  (on success)
--    "exit", code        (on call to os.exit())
--
function redir:pcall(cxt, func, ...)
   local ge, x = redir.getenv, redir.exit
   local iosave = {}

   for _,f in ipairs{"stdin", "stdout", "stderr"} do
      if cxt[f] then
         assert(io[f].redir == redir, "Help!  Someone broke my trapfiles...")

         iosave[f]  = io[f].f
         io[f].f = newRedirFile(cxt[f], cxt.tee and io[f].f)
      end
   end

   if cxt.environ then
      redir.getenv = function (key)
                        assert(type(key) == "string")
                        return cxt.environ[key]
                     end
   end

   redir.exit = errorExit

   local r = table.pack(xpcall(func, debug.traceback, ...))

   -- update cxt to reflect unread stdin
   if cxt.stdin then
      cxt.stdin = io.stdin.f.rdata
   end

   -- restore
   for _,f in ipairs{"stdin", "stdout", "stderr"} do
      if iosave[f] then
         io[f].f = iosave[f]
      end
   end

   redir.exit   = x
   redir.getenv = ge

   -- extract errorExit code (not a real error)
   if (not r[1]) and tostring(r[2]):match("^<<errorExit>>") then
      return "exit", errorExitCode
   end

   return table.unpack(r, 1, r.n)
end

return redir
