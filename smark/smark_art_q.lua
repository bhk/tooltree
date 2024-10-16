local qt = require "qtest"

require "smark_art"

local function imap(tbl, func)
   local o = {}
   for ndx, v in ipairs(tbl) do
      o[ndx] = func(v, ndx)
   end
   return o
end

local art, _art =
   qt.load("smark_art.lua", {
              "scan", "getHLines", "getVLines", "clearChars", "makeShape",
              "getPaths", "getLayers", "getRuns", "getShapes", "sortLayers",
              "rectsCover", "shapeContains", "inferShapes", "pathCrossesHV",
           })

local eq = qt.eq

-- split string into lines, removing prefix.  Returns nil if some line does
-- not start with prefix.  If nothing but space characters follow the last
-- newline, they are ignored.
local function splitLinesPRE(txt, prefix)
   local lines = {}
   for line, cr in txt:gmatch("([^\n]*)(\n?)") do
      if cr=="" and line:match("^ *$") then break end
      if line:sub(1,#prefix) ~= prefix then return nil end
      table.insert(lines, line:sub(#prefix+1))
   end
   return lines
end

local function splitLines(txt)
   local prefix = txt:match("^( *:)")
   return prefix and splitLinesPRE(txt,prefix) or splitLinesPRE(txt,"")
end


eq({"abc"," def"}, splitLines "  :abc\n  : def\n")
eq({"abc"," def"}, splitLines "abc\n def\n")
eq({"  :abc","   : def"}, splitLines "  :abc\n   : def\n")
eq({"abc","   :def"}, splitLines "abc\n   :def\n")

--------------------------------
-- getHLines

function qt.tests.getHLine()

   local function ht(txt, hlines)
      local hl = _art.getHLines(splitLines(txt))
      return eq(hlines, hl)
   end


   -- At least two graphics characters are required to make a line
   ht( " -   ",  {} )
   ht( " --  ",  {{0,1,3,"s"}} )
   ht( " --- ",  {{0,1,4,"s"}} )
   ht( " -,`- ", {{0,1,5,"s"}} )
   ht( " +-+ ",  {{0,1,4,"cCs"}} )
   ht( " +~+ ",  {{0,1,4,"cCsl"}} )
   ht( " +--+ ", {{0,1,5,"cCs"}} )
   ht( " +..+ ", {{0,1,5,"cCd"}} )
   ht( " `--, ", {{0,1,5,"cCrRs"}} )
   ht( "-->",    {{0,0,3,"As"}} )

   ht( "->+",     {{0,0,2,"AEs"}} )
   ht( "+<-",     {{0,1,3,"aes"}} )
   ht( "->+-",    {{0,0,2,"AEs"}, {0,2,4,"cs"}} )
   ht( "->+-+",   {{0,0,2,"AEs"}, {0,2,5,"cCs"}} )

   -- ## "o" must be adjacent to "-" or "|" to be treated as graphics.
   -- ## "o" adjacent to other letters will not be treated as graphics.

   ht( " o- ",  {{0,1,3,"os"}} )
   ht( " o+ ",  {} )
   ht( " -o ",  {{0,1,3,"Os"}} )
   ht( " o-o ", {{0,1,4,"oOs"}} )
   ht( " oo- ", {} )
   ht( " -o- ", {{0,1,3,"Os"}, {0,2,4,"os"}} )
   ht( "-oo- ", {} )
   ht( "foo-",  {} )

   ht( "---> ", {{0,0,4,"As"}} )
   ht( ">--> ", {{0,0,1,"A"},{0,1,4,"As"}} )
   ht( " <--> ", {{0,1,5,"aAs"}} )
   ht( "X-->||<--Y ", {{0,1,4,"As"}, {0,6,9,"as"}} )
   ht( "+-->--+",  {{0,0,4,"cAs"}, {0,4,7,"Cs"}} )
   ht( "+--<--+",  {{0,0,3,"cs"}, {0,3,7,"Cas"}} )

   ht( ".... ", {{0,0,4,"d"}} )
   ht( "...---...--- ", {{0,0,3,"d"},{0,3,6,"s"},{0,6,9,"d"},{0,9,12,"s"}} )
   ht( "...> ", {{0,0,4,"Ad"}} )

   ht( "---.-", { {0,0,3,"s"},{0,3,4,"d"},{0,4,5,"s"} })

   ht( "\n --- \n", {{1,1,4,"s"}} )
   ht( "\n\n\n\n --- \n", {{4,1,4,"s"}} )
   ht( "\n --- \n--", {{1,1,4,"s"}, {2,0,2,"s"}} )

   -- ## Require multiple hline characters to make a line, unless they are between "|" or ":"

   ht( "|-|", {{0,1,2,"s"}})
   ht( "a-b", {} )
   ht( "foo, bar, baz.", {} )

   ht( " ,---, ", {{0,1,6,"cCrRs"}} )
end

local function sortLines(vl)
   table.sort(vl, function(a,b) return a[1]*99+a[2] < b[1]*99+b[2] end)
   return vl
end


--------------------------------
-- getVLines

function qt.tests.getVLine()
   local example = {
      '+ | a b c d',
      '| +--+--+    ^',
      'v |  |  |    |  - q       ',
      '  v  o  +----+',
      '|   This is some',
      'V   text  '
   }

   local function vt(txtlines, vlines)
      local vl = _art.getVLines(txtlines)
      return eq(vlines, sortLines(vl))
   end

   vt(example, { {0,0,3,"cAs"}, {0,4,6,"As"}, {2,0,4,"As"}, {5,1,4,"cOs"},
                 {8,1,4,"cCs"}, {13,1,4,"Cas"} })


   -- ## '`' does not connect downwards, and ',' does not connect upwards

   local ex = {
      ' |  |  ',
      ' `  + ',
      ' +  ,  ',
      ' |  |  ',
   }
   local vl = _art.getVLines(ex)
   eq(4, #vl)

   -- ## Do not take letters or "," adjacent to other letters.

   local ex = {
      'vedi, vicio',
      '----+-+---|',
      '    | |    ',
      '    | |    ',
   }
   local vl = _art.getVLines(ex)
   eq({{4,1,4,"cs"},{6,1,4,"cs"},{10,1,2,"s"}}, vl)

end


--------------------------------
-- getPaths

local function gp(sample)
   local tl = splitLines(sample)
   local h, v  = _art.getHLines(tl), _art.getVLines(tl)
   --qt.printf("h = %Q\nv = %Q\n", h, v)
   return _art.getPaths(h, v)
end


function qt.tests.getPaths()

   local function checkPaths(sample, result)
      local p = gp(sample)
      table.sort(p, function (a,b) return qt.describe(a)<qt.describe(b) end)
      return eq(result, p)
   end

   local function S(t) t.flags = "s" ; return t end
   local function R(t) t.flags = "r" ; return t end
   local function Rc(t) t.flags = "cr" ; return t end
   local function N(t) t.flags = "" ; return t end
   local function Nc(t) t.flags = "c" ; return t end


   -- ## Ignore zero-length line (solitary connector vertical line here)

   local txt = [[
         : ---`
         :    |
   ]]
   checkPaths(txt, { S{ N{1,0.5}, Rc{4.5,0.5} },
                     S{ N{4.5,1}, N{4.5,2} }})

   -- ## Correctly translate line flags to point flags, and do not merge
   --    lines with conflicting flags (e.g. ">" touches "---")

   local txt = [[
         : >---  <--->+
      ]]
   checkPaths(txt, { N{ N{1,0.5}, {2,0.5,flags="a"}, flags=""},
                     S{ N{2,0.5}, N{5,0.5}},
                     S{ {7,0.5,flags="a"}, {12,0.5,flags="ae"}} })

   -- ## Join lines with other lines touching at connecting points "+", ",", "`"

   local txt = [[
      : +----+    +-->+-+  |
      : |  +-+--+   ^      |
      : `--+-`  |   |      |
      :    +----+   +      |
      ]]

   checkPaths(txt,
              { S{ Nc{11.5,0.5},{15,0.5,flags="ae"} },
                S{ {13.5,1,flags="a"}, Nc{13.5,3.5} },
                S{ Nc{15.5,0.5}, Nc{17.5,0.5} },
                S{ N{20.5,0}, N{20.5,4} },
                S{ Rc{6.5,2.5},Nc{6.5,0.5},Nc{1.5,0.5},Rc{1.5,2.5},Rc{6.5,2.5},
                   loop=true },
                S{ Nc{9.5,3.5}, Nc{9.5,1.5}, Nc{4.5,1.5}, Nc{4.5,3.5}, Nc{9.5,3.5},
                  loop=true } })


   -- ## Do not join dotted and solid lines

   local txt = [[
         . +...+
         . |
   ]]
   eq(2, #gp(txt))

   -- ## Keep track of lines that do not merge, yet share the same x,y

   local txt = [[
         :   <---+
         :       :
         :       :
   ]]
   eq(2, #gp(txt))


   -- ## Do not join lines at non-connecting points

   local txt = "-->--"
   checkPaths(txt,
              { S{ N{0,0.5}, {3,0.5,flags="a"} },
                S{ N{3,0.5}, N{5,0.5} } })


   -- ## Do not join lines at non-connecting points

   local txt = "--o--"
   checkPaths(txt,
              { S{ N{0,0.5}, {3,0.5,flags="o"} },
                S{ {2,0.5,flags="o"}, N{5,0.5} } })


   -- ##  Check path merges involving multiple segments

   local txt = [[
                    ,---,
       ,----,  ,--, |   |
       |  ,-+--`  | |   |
       `--+-+-----+-+---`
          | `-----` |
          `---------`
      ]]
   eq(1, #gp(txt))

end


----------------------------------------------------------------
-- shapes
----------------------------------------------------------------

-- sort layers by x coordinate of first rectangle and return unpack()
local function xsl(layers)
   local t = {}
   for k,v in ipairs(layers) do
      table.sort(v, function (a,b) return a.rects[1][1] < b.rects[1][1] end)
      t[k] = v
   end
   table.sort(t, function (a,b) return a[1].rects[1][1] < b[1].rects[1][1] end)
   return table.unpack(t)
end

local function printLayers(layers)
   print("layers:")
   for n = 1, #layers do
      local ll = layers[n]
      qt.printf("   layer[%d] = %s\n", n, tostring(ll))
      for n = 1, #ll do
         qt.printf("      [%d].rects = %Q\n", n, ll[n].rects)
      end
      print("      overs =", table.unpack(ll.overs or {}))
   end
end


function qt.tests.pathCrossesHV()
   eq(true,  _art.pathCrossesHV( {{0,1}, {2,1}, {2,2}, {1,2}, {1,0}},
                                 {{0,1}, {2,1}, {2,2}, {1,2}, {1,0}} ) )
   eq(false, _art.pathCrossesHV( {{0,1}, {2,1}, {2,2}, {1,2}, {1,3}},
                                 {{0,1}, {2,1}, {2,2}, {1,2}, {1,3}} ) )
   eq(true,  _art.pathCrossesHV( {{0,1}, {2,1}, {2,2}},
                                 {{1,0}, {1,2}} ) )
end


function qt.tests.shapes()
   local getShapes, getLayers = _art.getShapes, _art.getLayers

   -- ## Make non-rectangular polygons into shapes

   local txt = [[
         : ,-+
         : | +-+
         : +---+
      ]]
   local paths = gp(txt)
   local s = _art.makeShape( paths[1] )
   local r = s.rects
   eq(2, #r)
   eq({1.5, 0.5, 2.0, 1.0}, {r[1][1], r[1][2], r[1][3], r[1][4]})
   eq({1.5, 1.5, 4.0, 1.0}, {r[2][1], r[2][2], r[2][3], r[2][4]})

   -- ## Shape rectangles: corners must have round-ness of the path point
   --    for convex corners.  Not for concave corners or internal corners.

   eq("table", type(r[1].radius))
   eq(3, #r[1].radius)
   eq(nil, r[2].radius)

   -- ## Get shapes from paths

   local txt = [[
         : +-+
         : | +-+
         : +---+
      ]]
   local paths = gp(txt)
   local ss, paths = getShapes( paths )
   eq(0, #paths)
   eq(1, #ss)

   -- ## Group overlapping shapes into layers

   local txt = [[
       +----+
       |  +-+--+
       `--+-`  |
          +----+
      ]]
   local paths = gp(txt)
   eq(2, #paths)

   local ss = getShapes(paths)
   eq(2, #ss)

   local ll = getLayers(ss)
   eq(1, #ll)

   -- ## Shapes must be sorted from lower to topmost.

   local txt = [[
           +---------+
           | +---+   |
           | | +-+-+ |
           | +-+-+ | |
           |   +---+ |
           +---------+
      ]]
   local paths = gp(txt)
   local ss = getShapes(paths)
   local ll = getLayers(ss)
   local a, b = xsl(ll)
   eq(2, #ll)
   eq(1, #a)
   eq(2, #b)

   local txt = [[
           +-------+
           | +-+   |
           | +-+   |
           |     +-+-+
           +-----+-+ |
                 +---+
      ]]
   local paths = gp(txt)
   local ss = getShapes(paths)
   local ll = getLayers(ss)
   --printLayers(ll)
   eq(2, #ll)
   local a, b = xsl(ll)
   eq(2, #a)
   eq(1, #b)

   -- ## The "~" character in place of "-" disables polygon recognition.

   local txt = [[
       +~--+
       |   |
       +---+
   ]]
   local paths = gp(txt)
   eq(1, #paths)
   eq("sl", paths[1].flags)
   local ss = getShapes(paths)
   eq(0, #ss)


   -- ## Bug

   local txt = [[
         : ---`
         :    |
   ]]
   local paths = gp(txt)
   eq(2, #paths)
   local ss, p2 = getShapes(paths)
   eq(0, #ss)
   eq(2, #p2)
end


--------------------------------
-- clearChars

function qt.tests.clearChars()
   eq("a\t\td", _art.clearChars("abcd", 2,3))
   eq("abcd", _art.clearChars("abcd", 1,0))
end


--------------------------------
-- scan

function qt.tests.scan()
   local example = {
      '+ | a b c d',
      '| +-----+    ^',
      'v |     |    |  - q       ',
      '  v     +----+',
      '|   This is some',
      'V   text  '
   }

   local d = _art.scan(example)

   eq(19, d.columns)
   eq(6, d.rows)
   eq(4, #d.paths)
   eq({
      '. . a b c d',
      '. .......    .',
      '. .     .    .  - q       ',
      '  .     ......',
      '.   This is some',
      '.   text  '
      }, imap(d.txt, function (v) return v:gsub('\t','.') end))
end

--------------------------------
-- text layout rules

function qt.tests.textLayout()
   -- ## Three spaces delimit runs.  Two fall inside a run.

   -- ## Detect nearby graphics (no other intervening runs), setting
   --    'toleft', 'toright'

   -- ## Detect centering within graphics, setting 'mid'

   -- ## Detect starting/ending at same column

   local src = [[
        : | a  b   c |
        : |   xxx    |
        : |  yy      |
        : |  zzz     |
        : |   qq     |
   ]]

   local g = _art.scan( splitLines(src))
   local runs = _art.getRuns(g)

   eq({ {x=3,  y=0, text="a  b", atleft=1},
          {x=10, y=0, text="c",    atright=1},
          {x=5,  y=1, text="xxx",  mid=7.0},
          {x=4,  y=2, text="yy",   left=true},
          {x=4,  y=3, text="zzz",  left=true, right=true},
          {x=5,  y=4, text="qq",   right=true},
       }, runs)
end


function qt.tests.isCovered()

   local layers = {
      { {rects = {{0,0,10,10}}} }
   }
end


--------------------------------
-- shape inference

function qt.tests.rectsCover()
   eq(true, _art.rectsCover({ {0,0,10,1}, {0,1,10,1} },  {0,0,2,2}, 1))
   eq(true, _art.rectsCover({{6.5,0.5,10,5}}, {8.5,1.5,4,2}, 1) )

   eq(true, _art.shapeContains( {rects={{6.5,0.5,10,5}}},
                                {rects={{8.5,1.5,4,2}}} ) )
end


-- TODO:
--  1. don't pass shapes
--  2. test extend case & new edge case
--  3. don't infer when there are decorations
--
function qt.tests.infer()
   local getShapes, getLayers, inferShapes, sortLayers  =
      _art.getShapes, _art.getLayers, _art.inferShapes, _art.sortLayers

   local function gl(txt)
      local shapes, paths = getShapes( gp(txt) )
      return getLayers(shapes), paths
   end

   local function ti(numLayers, numPaths, txt)
      local layers, paths = gl(txt)
      --qt.printf("paths = %Q\n", paths)
      inferShapes(layers, paths, 1, 1)
      if numLayers ~= #layers then
         qt.printf("layers = %Q\n", layers)
         qt.printf("#layers = %Q\n", #layers)
      end
      qt._eq(numLayers, #layers, 2)
      qt._eq(numPaths, #paths, 2)
   end

   -- ## Extend first & last edges to a hidden vertex.

   local txt = [[
      +---+
      | A |--+
      +---+ B|
        |    |
        +----+
      ]]
   ti(2, 0, txt)

   -- ## Covering shape may not intersect unhidden vertices.

   local txt = [[
      +---+
      |  -+--+
      | | |  |
      +-+-+  |
        |    |
        +----+
      ]]
   ti(1, 1, txt)

   -- ## Don't convert a path with decorations into a shape.

   local txt = [[
      +---+
      | A |<-+
      +---+ B|
        |    |
        +----+
      ]]
   ti(1, 1, txt)

   -- ## Don't convert a path whose endpoint is connected to a shape or line

   local txt = [[
      +---+
      | A |--+
      +-+-+ B|
        |    |
        +----+
      ]]
   ti(1, 1, txt)

   -- ## Don't extend a line ending at a connecting point.

   local txt = [[
      +---+
      | A |+-+
      +---+ B|
        |    |
        +----+
      ]]
   ti(1, 1, txt)


   -- ## Infer a missing vertical edge perpendicular to first or last edge
   --    in path.

   local txt = [[
      +---+
      | A |--+
      +---+ B|
        +----+
      ]]
   ti(2, 0, txt)


   -- ## Other orientations

   local txt = [[
        +---+   +---+       +---+
      +---+ |   | +---+   +-|   |
      |   |-+   +-|   |   | +---+
      +---+       +---+   +---+
      ]]
   ti(6, 0, txt)

   local txt = [[
        +---+   +---+       +---+
      +---+ |   | +---+   + |   |
      |   | +   + |   |   | +---+
      +---+       +---+   +---+
      ]]
   ti(3, 3, txt)

   -- ## Layering

   -- "Layers" heretofore are actually groups, not necessarily ordered with
   -- respect to each other.  Groups INSIDE of other groups must be on top,
   -- and this is achieved by sorting by x coordinate, not by detecting
   -- containment.

   local txt = [[
      +---+          B is a rectangle obscured by A.
      | A |--+       When creating a shape for B we place it in a
      +---+ B|       layer below A.
        |    |
        +----+
      ]]
   local layers, paths = gl(txt)
   eq(1, #layers)
   local la = layers[1]
   inferShapes(layers, paths, 1, 1)
   eq(2, #layers)



   local txt = [[
         +----+
       +---+ B|       B and C are rectangles obscured by A, and they are
       |A  |--+--+    in the same layer; neither obscures the other.  The
       |   |--+  |    first one made a shape will create a new layer
       +---+     |    below A. The second must be added to the same layer.
         |    C  |
         +-------+
   ]]
   local layers, paths = gl(txt)
   eq(1, #layers)
   inferShapes(layers, paths, 1, 1)
   eq(2, #layers)
   eq(3, #layers[1] + #layers[2])


   local txt = [[
         +----+
      +--+-+ B|      A & B are in the same layer.
      |A | |--+--+   C could be obscured by A ,but not by B,
      |  +-+--+  |   so C cannot be inferred.
      +----+   C |
        +--------+
   ]]
   local layers, paths = gl(txt)
   inferShapes(layers, paths, 1, 1)
   eq(1, #paths)
   eq(1, #layers)
   eq(2, #layers[1])

   local txt = [[
         +----+
      +--+-+ B|      A & B are in the same layer.
      |A | |  |--+   C could be obscured by A and B.
      |  +-+--+  |   A shape will be created for C below the A&B layer.
      +----+   C |
        +--------+
   ]]
   local layers, paths = gl(txt)
   inferShapes(layers, paths, 1, 1)
   eq(0, #paths)
   eq(2, #layers)


   local txt = [[
      +---------+
      |A+---+   |      C is below B and above A.
      | | B |-+ |      The shape for C must fall in a new layer
      | +---+C| |      between A and B.
      |   +---+ |
      +---------+
      ]]
   local layers, paths = gl(txt)
   inferShapes(layers, paths, 1, 1)
   -- printLayers(layers)
   local A, B, C = xsl(layers)
   local a1, a2 = xsl(A.overs)
   qt.same(B,         a1)            -- B over A
   qt.same(C,         a2)            -- C over A
   qt.same(nil,       B.overs[1])    -- nothing over B
   qt.same(B,         C.overs[1])    -- B over C

   -- ## Test sortLayers

   local sl = sortLayers(layers)
   qt.same(B, sl[1])
   qt.same(C, sl[2])
   qt.same(A, sl[3])


   local txt = [[
      +-------+
      |A+---+ |      A is below B.  C is obscured by B, not A.
      | | B |-+--+   C must be in the same layer as A.
      | +---+ | C|
      |    |  |  |
      +----+--+  |
           +-----+
   ]]
   local layers, paths = gl(txt)
   inferShapes(layers, paths, 1, 1)
   local A, B = xsl(layers)
   qt.same(B, A.overs[1])
end


return qt.runTests()
