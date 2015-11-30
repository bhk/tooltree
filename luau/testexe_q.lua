local qt = require "qtest"
local TE = require "testexe"
local list = require "list"

local tmpdir = assert(os.getenv("OUTDIR"))
local function tmpname(f)
   return tmpdir .. "/" .. f
end

local luacmd = assert(os.getenv("LUA"))
local luaflagstr = os.getenv("LUA_FLAGS") or ''
local luaflags = {}
for word in luaflagstr:gmatch("[^ ]+") do
  table.insert(luaflags, word)
end

local function newE(cmd, flgs)
   local o = TE:new(cmd, os.getenv("testexe_q_v"))
   if type(flgs) == 'table' then
     -- Override 'exec' with one that prepends flgs
     local exec = o.exec
     o.exec = function(self, args)
       args = list.append(flgs, args)
       return exec(self, args)
     end
   end
   return o
end

local function pquote(str)
   return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"):gsub("%z", "%%z"))
end

----------------------------------------------------------------
-- Tests
----------------------------------------------------------------

-- ** writeFile() writes string to named file
--
-- ** Exec() runs a script when "@" prefixes the name
--    * captures stdout, stderr

local tmpfile = tmpname"testexe_echo.lua"

TE.writeFile(tmpfile, [[
for n = 0,#arg do
   print(n.."="..arg[n])
end
print(io.read("*a"):upper())
print "END"
]])

local f = newE("@"..tmpfile)
f.stdin = "abc"
f:exec("cat mouse")
f:expect[[
0=.-testexe_echo%.lua
1=cat
2=mouse
ABC
END
]]


package.path = tmpdir.."/?.lua;" .. package.path
local e = newE("@testexe_echo")
e.stdin = ""
e:exec("dog")
e:expect[[
0=testexe_echo
1=dog

END
]]


os.remove(tmpfile)


-- ** Exec() runs an executable
--    * captures stdout & stderr
--    * takes stdin from stdin

local lua = newE(luacmd, luaflags)
lua.stdin = "abc"
lua:exec{"-e", 'print("print"); io.stderr:write(io.read("*a"):upper()); print"HI"' }

--qt.printf("out = %Q\n", lua)
lua:expect("print\n")
qt.eq("ABC", lua.stderr)


-- ** Exec() quotes special characters when invoking an executable

local lua = newE(luacmd, luaflags)
local function echoTest(str)
   lua:exec{ '-e', 'print(([['..str..']]):gsub(" ","_"))' }
   lua:expect(pquote(str:gsub(" ","_")))
end


echoTest  "! \" # $ % & ' ( ) * + , - . : ; < = > ? @ [ \\ ] ^ _ ` { | } ~"

echoTest "( [ { <"

echoTest '"'

echoTest "%path%"

