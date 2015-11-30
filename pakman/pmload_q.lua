-- pmload_q

local qt = require "qtest"
local pl = require "pmload"

local lsw = pl.loadstringwith

function qt.tests.parsing()
   local function t(str)
      local _,a = load(str)
      qt.eq(a, select(2, lsw(str)))
      qt.eq(a, select(2, lsw(str, str)))
      qt.eq(a, select(2, lsw(str, str, {x=1})))
   end

   -- a) Valid chunks should work in loadstringwith().
   t("a=1")
   t("-- comment")

   -- b) Invalid chunks should produce the same error strings.
   t("a]b")
end


function qt.tests.upvalues()
   qt.eq(3, assert(lsw("return a+b", "", {a=1,b=2}))())
   qt.eq(3, assert(lsw("return a+b", nil, {a=1,b=2}))())
end


-- test require, dofile, readfile, etc., as returned by pmfuncs
--
function qt.tests.pmfuncs()
   local function resolve(rel, base)
      -- convert to lower case, so multiple names resolve to the same
      return base:gsub("/[^/]*$", "/"..rel:lower(), 1)
   end
   local data = {
      a = "A",
      b = "return 123",
      c = "return {a=1}",
      d = "local c = require('c'); return c.a",
      g = "return gvar"
   }
   local function read(uri)
      return data[uri:match("/([^/]*)$")]
   end

   local f = pl.pmfuncs("file:///foo", resolve, read)

   -- readfile, dofile, require

   qt.eq("A", f.readfile("a"))
   qt.eq(123, f.dofile("b"))
   qt.eq({a=1}, f.require("c"))

   -- Modules are system singletons: all compiled chunks share the same set
   -- of loaded modules.

   local c = f.require"c"
   c.a = 2
   qt.eq(2, f.dofile("d"))

   -- equivalent URIs should be treated as the same module

   qt.same(f.require("c"), f.require("C"))

   -- compiled chunks use *user globals*, not default globals

   local setgvar = f.loadstring("gvar = 7")
   setgvar()
   qt.eq(7, pl.userGlobals.gvar)
   qt.eq(nil, rawget(_G, "gvar"))
   qt.eq(7, f.dofile("g"))

end


return qt.runTests()
