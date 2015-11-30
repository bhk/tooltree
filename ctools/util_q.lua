local U = require "util"
local qt = require "qtest"

local eq = qt.eq
local tests = qt.tests

function tests.cleanPath()
   local function tcp(a,b)
      return eq(b, U.CleanPath(a))
   end

   tcp("./", ".")

   tcp("a/.", "a")
   tcp("./b", "b")
   tcp("/./b", "/b")
   tcp("a/./b", "a/b")
   tcp("a./b", "a./b")
   tcp("a/.b", "a/.b")

   tcp("a/..", ".")
   tcp("a/b/..", "a")
   tcp("../b", "../b")
   tcp("a/../b", "b")
   tcp("/a/../b", "/b")
   tcp("b/..a", "b/..a")
   tcp("b../a", "b../a")
   tcp("b../..a", "b../..a")
   tcp("b../..a", "b../..a")

   tcp("/..", "/..")
   tcp("a/b/c/d/../../..", "a")
   tcp("a/b/c/d/../../e", "a/b/e")

   tcp("/a/./../b", "/b")
   tcp("./../b", "../b")
   tcp("/a/b/./.././c", "/a/c")

   tcp("a/.././.", ".")
   tcp("a/.../b", "a/.../b")

   tcp("./../x/../../a", "../../a")

   tcp("././../a", "../a")
end

function tests.stringSplit()
   local function test(str, pat, tbl)
      local t = U.stringSplit(str, pat)
      for k,v in pairs(tbl) do
	 assert(t[k] == v)
      end
      for k,v in pairs(t) do
	 assert(tbl[k] == v)
      end
   end

   test("1,2,", ",", {"1", "2", ""} )
   test("1,2,3", ",", {"1", "2", "3"} )
end

function tests.tableEQ()
   assert( U.tableEQ( {}, {} ) )
   assert( U.tableEQ( {2, 1, a=5},  {2, 1, a=5} ) )
   assert( not U.tableEQ( {2, c=3}, {c=3} ) )
   assert( not U.tableEQ( {2},      {2, c=3} ) )
end

function tests.stringBegins()
   assert( U.stringBegins("", "") )
   assert( U.stringBegins("abcde", "") )
   assert( U.stringBegins("abcde", "a") )
   assert( U.stringBegins("abcde", "abcde") )
   assert( not U.stringBegins("abcde", "abcdef") )
end

function tests.stringEnds()
   assert( U.stringEnds("", "") )
   assert( U.stringEnds("abcde", "") )
   assert( U.stringEnds("abcde", "e") )
   assert( U.stringEnds("abcde", "abcde") )
   assert( not U.stringEnds("abcde", "xabcde") )
end

function tests.ResolvePath()
   local r = { U.ResolvePath("/a/b/", "c", "c\\d", "c:/foo", "\\foo/a", "../foo", "x/y:z", ".." ) }
   eq("/a/b/c", r[1])
   eq("/a/b/c/d", r[2])
   eq("c:/foo", r[3])
   eq("/foo/a", r[4])
   eq("/a/foo", r[5])
   eq("/a/b/x/y:z", r[6])
   eq("/a", r[7])

   eq("../../a", U.ResolvePath(".", "../x/../../a"))

   eq("../a", U.ResolvePath(".", "./../a"))

   -- Non-absolute start paths not supported
--[[
   eq(".", U.ResolvePath("a", ".."))
   eq(".", U.ResolvePath("a/", ".."))
   eq(".", U.ResolvePath("a/b", "../.."))
   eq(".", U.ResolvePath("a/b/", "../.."))
   eq("..", U.ResolvePath("a/b", "../../.."))
]]
end

function tests.tfold()
   local t = { [8]= 1, [16] = 2, [32] = 4}
   eq(63, U.tfold(function(k,v,b) return k + v + b end, 0, t))
   eq(0,  U.tfold(function(k,v,b) return k + v + b end, 0, {}))
end

function tests.tcount()
   local t = { "a", [8]= 1, [16] = 2, [32] = 4}
   eq(4, U.tcount(t))
end

function tests.ifold()
   local t = { "a", "c", "b", x="d" }
   eq("acb", U.ifold(function(v,b) return b .. v end, "", t))
   eq("",    U.ifold(function(v,b) return b .. v end, "", {}))
end

function tests.imap()
   local t = U.imap( {"a","b"}, function (a) return a..a end)
   eq("aa,bb", table.concat(t, ","))
end

function tests.arrayFromTable()
   local t = U.arrayFromTable( {a=1, b=2, c=3}, function (x) return x end)
   table.sort(t)
   eq("a,b,c", table.concat(t, ","))
end

function tests.tableFromArray()
   local t = U.tableFromArray({"a","b","c"}, function(k,v) return v,k end)
   eq(1, t.a)
   eq(3, t.c)
end

return qt.runTests()

