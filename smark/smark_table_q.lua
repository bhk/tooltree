local qt = require "qtest"
local doctree = require "doctree"
local Source = require "source"

require "smark_table"
local smark_table, _st = qt.load("smark_table.lua", {
                                    "scanRow", "newXYText",
                                    "makeTable", "getOutermostLines",
                                 })

local E = doctree.E
local eq = qt.eq


local function newSource(str)
   return Source:newString(nil, str)
end

function qt.tests.GetXY()
   local xyt = _st.newXYText(newSource("abc\ndef\ngh"))
   eq({1,1}, {xyt:getXY(1)})
   eq({4,1}, {xyt:getXY(4)})
   eq({1,2}, {xyt:getXY(5)})
   eq({1,1}, {xyt:getXY(1)})
   eq({1,3}, {xyt:getXY(9)})
end


function qt.tests.SourceRect()
   local ex = [[
X
abcdeghijklm

1234567890
abcdeghijklmnopqrstuvwxyz
]]

   local xyt = _st.newXYText(newSource(ex))

   local s = xyt:sourceRect(8, 2, 20, 4)
   eq("ijklm\n\n890\n", s.data)
end


function qt.tests.scanRow()
   local function gr(vl,y1,y2)
      local row = {}
      _st.scanRow(vl, y1, y2, function (...) table.insert(row, {...}) end)
      return row
   end
   local vl = {
      {1, 2, 10},
      {5, 5, 10},
      {9, 2, 10},
   }

   eq( { {1,5,1,""}, {5,9,1,""} } , gr(vl, 6, 7) )
   eq( { {1,9,2,""} } ,             gr(vl, 2, 10) )
   eq( { {1,5,1,""}, {5,9,1,""} } , gr(vl, 5, 10) )
end


function qt.tests.getOutermostLines()
   eq( { { {1,1,10} },
         { {1,1,9}, {10,1,9} } },
       { _st.getOutermostLines( { {1,1,10}, {99,1,1} },
                                { {1,1,9}, {10,1,9}, {5, 5, 10} } ) } )
end



local function mktbl(...)
   return doctree.visitElems(_st.makeTable(...), function (node) node._source = nil end)
end


function qt.tests.makeTable()

   local t1 = [[
+-----+-----+
| A=B | C++ |
+-----+-----+
]]

   eq( E.table{
          E.tr { E.td{ E.p{"A=B"} }, E.td{ E.p{"C++"} } },
       }, mktbl(newSource(t1)))

   -- ROWSPAN and COLSPAN

   local t2 = [[
   +-----+---+
   |     | B |
   |     +---+
   |  A  | C |
   +--+--+   |
   |D |E |   |
   +--+--+---+
   ]]

  eq( E.table{
         E.tr { E.td{ E.p{"A"}, rowspan=2, colspan=2}, E.td{ E.p{"B"} } },
         E.tr { E.td{ E.p{"C"}, rowspan=2} },
         E.tr { E.td{ E.p{"D"} }, E.td{ E.p{"E"} } },
      }, mktbl(newSource(t2)))
end



function qt.tests.nest()
   local t2 = [[
   +-------+
   | . +-+ |
   | . | | |
   | . +-+ |
   +-------+
   ]]

  eq( E.table{ E.tr { E.td { E.pre{ "+-+ \n| | \n+-+ \n"}}}},
      _st.makeTable(newSource(t2)))
end


function qt.tests.th()
   local t2 = [[
   +---+---+
   | A | B |
   +===+---+
   ]]

   eq( E.table {
          E.tr { E.th{ E.p{"A"} }, E.td{ E.p{"B"} } }
       },
       _st.makeTable(newSource(t2)))
end

return qt.runTests()
