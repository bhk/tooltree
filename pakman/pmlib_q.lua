local qt = require "qtest"

local pl, _pl = qt.load("pmlib.lua", {"listShortNames"})  -- @require pmlib

function qt.tests.map()
   qt.eq({"/pakman/a/b/c"}, pl.mapLong( {rootPath="/a/b/c"} ))
   qt.eq({"/pkg/c", "/pkg/b-c", "/pkg/a-b-c"},  pl.mapShort( {rootPath="/a/b/c"} ) )
end

-- 'gen' and 'parse' are more fully tested in pmuri_q.  Just make
-- sure pmlib has the right values.
function qt.tests.map()
   qt.eq("p4://h/p/q",  pl.uriGen{ scheme="p4", host="h", path="/p/q"} )
   qt.eq({ scheme="p4", host="h", path="/p/q"}, pl.uriParse("p4://h/p/q") )
end

function qt.tests.shortNames()
   local junkDirs = {
      main = true,
      latest = true,
      dev = true,
      tip = true,
      head = true
   }

   local function st(o, i)
      return qt.eq(o, _pl.listShortNames(i, junkDirs))
   end

   st( {"foo", "foo/main", "x/foo/main"},                      "//x/foo/main")
   st( {"foo", "foo/main", "x/foo/main", "x/foo/main/latest"}, "//x/foo/main/latest")
   st( {"foo/1.0", "foo/dev/1.0", "x/foo/dev/1.0"},            "//x/foo/dev/1.0")
   st( {"foo/1.0p1", "foo/dev/1.0p1", "x/foo/dev/1.0p1"},      "//x/foo/dev/1.0p1")
   st( {"src", "foo/src", "foo/src/main", "x/foo/src/main"},   "//x/foo/main/src")
end


function qt.tests.hash()
   qt.eq("AAA", pl.hash("str", 3, "A"))
   qt.eq(1, #pl.hash("str", 1))

   -- test uniformity

   local hashes = {}
   local size = 3
   local function add(str)
      local h = pl.hash(str, size)
      qt.eq(size, #h)
      qt.eq(nil, hashes[h])
      hashes[h] = true
   end

   for n = 1, 22 do
      add( ("a"):rep(n) )
   end
   for n = 0, 255 do
      add( "abcdef"..string.char(n) )
   end
   add( ("z"):rep(1000) .. "x")
   add( ("z"):rep(1000) .. "y")
end


return qt.runTests()
