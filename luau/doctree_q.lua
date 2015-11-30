local qt = require "qtest"
local doctree = require "doctree"

local E = doctree.E


function qt.tests.E()
   qt.eq( {_type="a","x"},  E.a{"x"})
   qt.same(E.x, E.x)
   qt.eq(E.foo{}._type, "foo")
end


function qt.tests.treeConcat()
   qt.eq( "hi", doctree.treeConcat"hi")
   qt.eq( "hi there",  doctree.treeConcat{"hi", {" ", {"th", "e"},"re"}})
end


function qt.tests.visitElems()
   local doc = {
      E.a {
         E.x { "X"},
         E.y { "Y" },
      },
      E.b {
         E.x { "X" }
      }
   }

   local text = ""
   local function o(node)
      for _, ch in ipairs(node) do
         if type(ch) == "string" then
            text = text .. ch
         end
      end
   end

   doctree.visitElems(doc, o)
   qt.eq(text, "XYX")

   text = ""
   doctree.visitElems(doc, o, "x")
   qt.eq(text, "XX")
end


return qt.runTests()
