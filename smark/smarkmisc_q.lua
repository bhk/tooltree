local qt = require "qtest"
local M = require "smarkmisc"
local doctree = require "doctree"

local E = doctree.E

function qt.tests.E()
   qt.eq( {_type="a","x"},  E.a{"x"})
   qt.same(E.x, E.x)
end


function qt.tests.rtrim()
   local function e(i,o)
      return qt.eq(o, M.rtrim(i))
   end

   e("1  2", "1  2")
   e("  12", "  12")
   e(" 12 \t", " 12")
   e(" 12\t ", " 12")
   e("  ", "")
   e("  ", "")
end

function qt.tests.expandTabs()
   local function e(i,o)
      return qt.eq(o, M.expandTabs(i))
   end

   e("\t",              "        ")
   e("\tb",             "        b")
   e("a\tb",            "a       b")
   e(" a\tb",           " a      b")
   e("  a\tb",          "  a     b")
   e("   a\tb",         "   a    b")
   e("    a\tb",        "    a   b")
   e("     a\tb",       "     a  b")
   e("      a\tb",      "      a b")
   e("       a\tb",     "       a        b")
   e("\t\tb",           "                b")
   e("  a\t      a\tb", "  a           a b")
   e("a b ",            "a b ")
   e("xyz\n\tb",          "xyz\n        b")
end


function qt.tests.findRowCol()
   qt.eq({3,4}, {M.findRowCol("abc\ndef\nghijkl",12)})
   qt.eq({0,0}, {M.findRowCol("abc\ndef\nghijkl",0)})
end


function qt.tests.url()
   qt.eq("a%25b%20c%26%3b%3f%23", M.urlEncode("a%b c&;?#"))

   local s = [[!"#$%&'()*+,-./0123456789:;<=>?@[\]^_`{|}~]]
   local e = M.urlEncode(s)
   local de = e:gsub("%%(%x%x)", function (s)
                                    return string.char(tonumber(s, 16))
                                 end)
   qt.eq(s, de)

   qt.eq(e, M.urlNormalize(e))
   qt.eq("a%20b", M.urlNormalize("a b"))
end



return qt.runTests()
