----------------------------------------------------------------
-- TestExe: utilities for executing commands and capturing output
--
-- Synopsis:
--
--    local te = TestExe:new("echo", true)   -- true => output log messages
--    te "arg1 arg2"                     -- execute command with args
--    te:exec("arg1 arg2")               -- execute command with args (alt)
--    te:expect("result_pattern")        -- test output
--
-- A command name beginning with "@" identifies a Lua command to be loaded
-- and called directly within the same Lua VM, calling it and capturing its
-- output as if it were invoked from the command line.
--
-- Args are provided as a string of space-delimited arguments.  TextExe
-- will quote and escape characters as necessary for the underlying shell
--
--    Note: Users of this feature may need to require "redir" and explicitly
--    call redir:hook() early during the startup phase if they find some
--    output not being captured.  See redir.lua for more info.
--
--    Note: If code executed within the command modifies state that outlives
--    the command (e.g. members or required modules) then changes made
--    during one run can unpredictably affect subsequent runs.  Fixing this
--    would require an overhaul of testexe/redir, providing an encapsulated
--    simulation of the module system (i.e. the implemetation of 'require').
--
-- Public instance attributes:
--     bVerbose = true to enable logging
--     bTee     = if true, tee command output to original stdout, stderr
--     bBinary  = if true, do NOT convert CRLF to LF on Windows
--     out      = stdout output from previous Exec/Capture
--     stderr   = stderr output from previous Exec/Capture (only supported
--                when capturing from Lua with "@..."; nil otherwise)
--     stdin    = string to use as stdin (or nil to use default stdin)
--     filePrefix = prefix for temporary file names
--     retval   = value returned by function, or passed to os.exit()
--                [only supported for "@..." commands]
--
-- Public class members:
--     grep, sort, lines = utility functions
--
-- Object methods have initial capitals; call with:    obj:name()
-- Simple closures have initial lowercase; call with:  obj.name()
--
----------------------------------------------------------------

local Object = require "object"
local redir = require "redir"
local xe = require "xpexec"

----------------------------------------------------------------
-- Utilities
----------------------------------------------------------------


local function pl(txt, prefix)
   if not txt then return end
   txt = txt:gsub("\r\n", "\n")
   txt = txt:gsub("([^\n]*)\n", " | %1\n")
   return txt:gsub("([^\n]+)$", " * %1\n")   -- unterminated last line
end

-- array --> array
local function grep(lines, pat, isNegative)
   local t = {}
   for _,line in ipairs(lines) do
      local m = line:match(pat)
      if not m == not not isNegative then
         table.insert(t, m)
      end
   end
   return t
end

-- non-destructive sort; returns a newly-created, sorted table
local function sort(tbl,...)
   local t = {}
   for _,v in ipairs(tbl) do
      table.insert(t,v)
   end
   table.sort(t,...)
   return t
end

-- Return lines from txt
-- fn can filter/transform lines (return nil -> not added to array)
local function lines(txt)
   local t = {}
   for line in txt:gmatch("([^\r\n]*)\r?\n") do
      table.insert(t, line)
   end
   return t
end

local function readFile(filename)
   local ftext
   local f = io.open(filename, "rb")
   if f then
      ftext = f:read("*a")
      f:close()
   end
   return ftext
end

local function writeFile(filename, data)
   local f = io.open(filename, "wb")
   if f then
      f:write(data)
      f:close()
      return true
   end
end

local function diff(a, b, lvl)
   lvl = 1 + (lvl or 1)
   if a == b then return end
   local la, lb = pl(a or "(empty)"), pl(b or "(empty)")
   if la ~= lb then
      print("Expected:\n" .. la)
      print("Got:\n" .. lb)
      error("Content does not match.", lvl)
   end
end


local function pipeRead(str)
   local p = io.popen(str, "r")
   local out = p:read("*a")
   p:close()
   return out
end


----------------------------------------------------------------
-- TestExe
----------------------------------------------------------------


local TestExe = Object:new()


package.searchers = package.searchers or package.loaders -- Lua 5.1 compat

local function loadFromPath(name)
   for _, searcher in ipairs(package.searchers) do
      local loader = searcher(name)
      if type(loader) == "function" then
         return loader
      end
   end
end


function TestExe:initialize(cmdName, bVerbose, tmpName)
   if cmdName:sub(1,1) == "@" then
      cmdName = cmdName:sub(2)
      -- preserver error message
      local chunk, err = loadfile(cmdName)
      if not chunk then
         chunk = loadFromPath(cmdName)
      end
      if not chunk then
         error(err)
      end
      self.chunk = chunk
      redir:hook()
   end
   self.cmdName = cmdName
   self.bVerbose = bVerbose
   self.filePrefix = tmpName or ".testexe"
end


function TestExe:log(fmt, ...)
   if self.bVerbose then
      io.write( fmt and string.format(fmt,...) or "Out:\n" .. pl(self.out) )
   end
end


-- Construct string from table of arguments (as returned by parseCommand)
--
function TestExe:makeExecString(argtbl)
   local cmd = xe.quoteCommand(argtbl[0], argtbl)
   cmd = cmd ..  " 2> " .. self.filePrefix.."stderr"
   if self.stdin then
      cmd = cmd .. " < " .. self.filePrefix.."stdin"
   end
   return cmd
end


-- Invoke command and record its output in self.out.
--
-- If the command name begins with "@", the rest of the command is taken as
-- the name of a Lua file, which is then loaded and executed using Capture().
--
-- When "@..." commands are used, `self.checkExit` controls how the
-- command's exit code is checked:
--    nil      => ignore exit code
--    true     => exit code must not be a non-zero number
--    false    => exit code must be a non-zero number
--    <number> => exit code must match self.checkExit exactly
--
function TestExe:exec(args)
   -- Make 'arg' table:  t[0] = command, t[1] = first arg, ...
   local argtbl = { [0] = self.cmdName }
   if type(args) == "table" then
      for _,a in ipairs(args) do
         table.insert(argtbl, a)
      end
      args = table.concat(argtbl, " ")
   else
      for a in args:gmatch("[^ ]+") do
         table.insert(argtbl, a)
      end
   end

   if self.chunk then

      -- Invoke the program via pcall (we've loaded the Lua module directly)

      self:log("pcall: %s %s\n", self.cmdName, args)
      local argsav = _G.arg
      _G.arg = argtbl

      local cxt = {
         stdout = {},
         stderr = {},
         stdin = self.stdin,
         tee = self.bTee
      }
      local succ, ret = redir:pcall(cxt, self.chunk, table.unpack(argtbl))

      self.out = table.concat(cxt.stdout)
      self.stderr = table.concat(cxt.stderr)
      self.retval = ret

      if not succ then
         print(self.out)
         print(ret)
         error("TestExe: error in exec'ed function")
      end

      local checkExit = self.checkExit
      local status = tonumber(ret) or 0
      if tonumber(checkExit) and checkExit ~= status or
         type(checkExit) == "boolean" and checkExit ~= (status == 0)
      then
         print("stdout: " .. pl(self.out))
         print("stderr: " .. pl(self.stderr))
         if succ == "exit" then
            error("command called os.exit(" .. tostring(ret) .. ")", 2)
         else
            error("command returned: " .. tostring(ret), 2)
         end
      end

      _G.arg = argsav
      if not self.bTee then
         self:log()
      end
   else

      -- Invoke the program as an executable

      local execString = self:makeExecString( argtbl )
      if self.stdin then
         writeFile(self.filePrefix.."stdin", self.stdin)
      end

      self:log("Exec: %s\n", execString)
      self.out = pipeRead( execString )

      if self.stdin then
         os.remove(self.filePrefix.."stdin")
      end
      self.stderr = readFile(self.filePrefix.."stderr") or ""
      os.remove(self.filePrefix.."stderr")
      self:log()

      self.retval = nil
   end

   if xe.isWindows() and not self.bBinary then
      self.out = self.out:gsub("\r\n", "\n")
      self.stderr = self.stderr:gsub("\r\n", "\n")
   end

   return self.out
end


--  te(args) is shorthand for te:exec(args)
--
TestExe.__call = TestExe.exec


-- Expect command output to match a pattern.  Returns all captures.
--
function TestExe:expect(pat, lvl)
   local caps = { self.out:match(pat) }
   if not caps[1] then
      io.write("Error: In output:\n" .. pl(self.out) )
      io.write("Did not see:\n" .. pl(pat) )
      if self.stderr then
         io.write("With stderr:\n" .. pl(self.stderr) )
      end
      error("assertion failed", (lvl or 1) + 1)
   end
   return table.unpack(caps)
end

-- Diff against a text file
--   exp = "<filename>" or "=<contents>"
--
function TestExe:diff(exp, lvl)
   if exp:sub(1,1) ~= "=" then
      exp = readFile(exp)
   else
      exp = exp:sub(2)
   end
   diff(exp, self.out, 1+(lvl or 1))
end

-- Search for pattern in output lines. Return array of captures (one per line).
--
function TestExe:filter(pat)
   return grep( lines(self.out), pat )
end


-- Change working directory of the current process, and fix up package.path
-- so "require" still works.
--
function TestExe.chdir(dir)

end


-- utility functions

TestExe.lines = lines
TestExe.prefixLines = pl
TestExe.grep = grep
TestExe.sort = sort
TestExe.readFile = readFile
TestExe.writeFile = writeFile
TestExe.diffStrings = diff

return TestExe
