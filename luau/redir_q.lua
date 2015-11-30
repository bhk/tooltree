local redir = require "redir"
local qt = require "qtest"

redir:hook()
local function p(...)
   redir._print( qt.format(...) )
end


-- ** Redirect io.stdout, io.write, and print
-- ** Redirect io.stderr
-- ** Redirect io.read & io.stdin
-- ** stdin can be specified as a string
-- ** stdout and stderr can be specified as tables
local io_stdout = io.stdout
local io_stdin  = io.stdin
local io_write  = io.write
local io_read   = io.read

local function testIO(str)
   -- test global io.read()
   local a = io.read('*l')

   -- test global print()
   print("*l: " .. a)

   -- test global io.stdin
   a = io.stdin:read(6)

   -- test global io.write
   io.write("6: " .. a .. "\n")

   -- test saved global io_read()
   a = io_read(5)
   io.write("5: " .. a .. "\n")

   -- test saved global io_stdin
   a = io_stdin:read(5)
   io.stdout:write("*a: " .. a .. "\n")

   -- test saved global io_write() and global io.type()
   io_write(io.type(io.stdin).."\n")

   -- test global io.stdin:close()
   io.stdin:close()

   -- test saved globals io_stdout and io_stdin
   io_stdout:write(io.type(io_stdin).."\n")
   io.stderr:write("Done: "..str)

   -- test trapfile:flush()
   io.stderr:flush()

   return 7
end

local cxt = {
   stdin = "hello\nworld dude rest",
   stdout = {},
   stderr = {}
}
local succ, results = redir:pcall(cxt, testIO, "arg")

if not succ then
   error(results)
end

qt.eq(succ, true)
qt.eq(7, results)
qt.eq("*l: hello\n6: world \n5: dude \n*a: rest\nfile\nclosed file\n", table.concat(cxt.stdout))
qt.eq("Done: arg", table.concat(cxt.stderr))


-- ** Trap os.exit() calls

local function testExit()
   print("One")
   print("Two")
   os.exit(3)
end

local cxt = {
   stdout = {},
   stderr = {}
}
local succ, results = redir:pcall(cxt, testExit)

qt.eq("exit", succ)
qt.eq(3, results)
qt.eq("One\nTwo\n", table.concat(cxt.stdout))


-- ** Retain args & return values

local t = table.pack( redir:pcall(cxt, function (...) return ... end, 1, nil) )
qt.eq({n=3, true, 1, nil}, t)
