local qt = require "qtest"
local T = qt.tests

require "html2d"
local Html2D, _H2D = qt.load("html2d.lua", {"Point", "chooseSides"})

local Point = _H2D.Point

local function patCount(pat, str)
   return select(2, str:gsub(pat, ""))
end


--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------
local T = qt.tests


function T.Point()
   qt.eq({3.0,2.0},   ((Point(7,2) - {2,1}) + {1,3})/2 )
   qt.eq(true,    Point(2,3) == Point(2,3))
   qt.eq("(1,2)", tostring(Point(1,2)) )
end


function T.chooseSides()
   local function tcs(r, a,b,c,d)
      a,b,c,d = a and Point(a), b and Point(b), c and Point(c), d and Point(d)
      local o = {_H2D.chooseSides(a, b, c, d)}
      qt._eq(r, o, 2)
   end

   -- skip B when between A&C, inclusive
   tcs( {1},                  {0,0}, {1,1}, {3,3}, {4,5})
   tcs( {1},                  {0,0}, {0,0}, {3,3})
   tcs( {1},                  {0,0}, {3,3}, {3,3}, {4,5})

   -- Draw only A-B when C reverses
   tcs( {1, {0,2}},           {0,0}, {0,2}, {0,1})

   -- Draw only A-B when B-C is neither parallel nor perpendicular
   tcs( {1, {2,0}},           {0,0}, {2,0}, {3,1} )

   -- Draw two sides
   tcs( {2, {1,0}, {1,1}},    {0,0}, {1,0}, {1,1})
   tcs( {2, {1,0}, {1,-1}},   {0,0}, {1,0}, {1,-1})
   tcs( {2, {1,1}, {0,2}},    {0,0}, {1,1}, {0,2})

   -- Draw two sides when third cannot be drawn
   tcs( {2, {1,0}, {1,1}},    {0,0}, {1,0}, {1,1}, {2,1})
   tcs( {2, {1,0}, {1,-1}},   {0,0}, {1,0}, {1,-1}, {2,-1})

   -- Stop short of third point when rounded and fourth point cannot be drawn
   tcs( {1, {1,0}, {1.0,1.0,mid=true}},  {0,0}, {1,0}, {1,2,round=true}, {2,2})

   -- Draw three sides
   tcs( {3, {1,0}, {1,1}, {0,1}},    {0,0}, {1,0}, {1,1}, {0,1})
   tcs( {3, {1,0}, {1,-1}, {0,-1}},  {0,0}, {1,0}, {1,-1}, {0,-1})
   tcs( {3, {1,1}, {0,2}, {-1,1}},   {0,0}, {1,1}, {0,2}, {-1,1})

   -- Stop short of fourth point
   tcs( {2, {1,0}, {1,1}, {0,1, mid=true}},
                              {0,0}, {1,0}, {1,1}, {-1,1,round=true})
end


function T.Path()
   -- ## Consecutive aligned points will generate one line, not many.
   --    [The difference is not visible in this case, but this handling
   --    is important in more complicated cases where corner rounding
   --    is involved.]

   local gc = Html2D:new()
   gc:setSize(0,0)
   gc:path{ {10,10}, {10,20}, {10,30}, {10,40} }
   local o = gc:genHTML()
   qt.eq(3, patCount("<div", o))


   -- ## When a path reverses along a line, all points will be covered.
   --
   local gc = Html2D:new()
   gc:setSize(0,0)
   gc:path{ {10,10}, {100,10}, {50,10}, {50,20}, radius=10}
   local o = gc:genHTML()
   qt.eq(4, patCount("<div", o))
end


local rv = qt.runTests()
if rv ~= 0 then
  return rv
end

--------------------------------------------------------------------------------
-- Sample output (for manual verification, or for example purposes)
--------------------------------------------------------------------------------

local snippets = {

   { 20, 20, [[
           gc:strokeX(10, 10, 5)
     ]]},

   -- Edges should fall at middle of grid lines
   {  50,  40, 'gc:fillRect( 10,10, 30,20 )' },

   { 100,  50, 'gc:rect( 10,10, 80,30, {strokeStyle="solid"})' },

   { 100, 110, [[
           -- box
           gc:rect(10, 10, 80, 40, {
                      strokeStyle = "dashed", lineWidth = 2,
                      text = "TEXT\nLINE 2", textBG = "white", textColor = "blue"
                   })

           gc:rect(10, 70, 60, 30,
                   { fill = true, strokeStyle = "solid", text = "Hello" } )
     ]] },

   { 100,  100, [[
           -- xwedge
           gc:wedge( 10, 20, 40, 10, 20)
           gc:wedge( 90, 30, -30, 20, 10 )
           gc:wedge( 30, 50, 40, 10, 20, true)
           gc:wedge( 80, 90, -30, 20, 10, true )
     ]]},

   { 100,  230, [[
           -- arrows
           local function A(x, y, l, w, t)
              t = t or {}
              t.arrowLength, t.arrowWidth = l, w
              local n = gc:arrow({x, y}, {50,y}, t)
              gc:path{ {x+n*gc.lineWidth, y}, {x < 50 and x+80 or x-80, y} }
           end

           A(10,  30, 50, 40, {open=true})
           A(90,  90, 20, 80, {open=true})
           A(10, 140, 40, 60, {open=true, noBottom=true})
           A(90, 160, 30, 60, {noTop=true})
           A(10, 200, 40, 40)
     ]] },

   {  90, 110,  [[
           -- linestyles
           gc:path{ {10,10}, {80,10}, lineStyle = "dashed" }
           gc:path{ {10,30}, {80,30}, lineStyle = "dotted" }
           gc:path{ {10,50}, {80,50}, lineStyle = "double" }
           gc:path{ {10,70}, {80,70}, lineWidth = 6 }
           gc:path{ {10,90}, {80,90}, lineWidth = 16 }
     ]] },

   { 100, 100, [[
           -- circle?
           gc:path{ {50,10}, {90,10}, {90,90}, {10,90}, {10,10}, {50,10},
                    radius = 50 }
     ]] },

   { 100, 100, [[
           -- circle
           gc:circle(50, 50, 40)
           for i = 1, 6 do
              for j = 1, i do
                 gc:circle(j*10 - 5, i*10 - 5, i/2, {lineWidth=j/2, strokeColor="#555"})
              end
           end
     ]] },

   { 100, 100,  [[
           -- three-sided paths
           gc:path{ {10,10}, {40,10}, {40,40}, {10,40} }
           gc:path{ {60,10}, {90,10}, {90,40}, {60,40}, radius=20 }
           gc:path{ {10,90}, {20,90}, {20,60}, {50,60}, {50,90}, {80,90}, {80,75}, radius=40 }

     ]] },


   { 100, 100,  [[
           gc:path{ {10,10}, {40,10} }
           gc:path{ {60,10}, {90,10}, {90,40} }
           gc:path{ {10,50}, {10,30}, {50,30}, {50,70}, {90,70}, {90,90}, {10,90}}
     ]] },

   { 100, 100,  [[
           -- roundpath
           gc.lineWidth = 6
           gc:path{ radius=10, {10,10}, {40,10} }
           gc:path{ radius=10, {60,10}, {90,10}, {90,40} }
           gc:path{ radius=10, {10,50}, {10,30}, {50,30}, {50,70}, {90,70}, {90,90}, {10,90}}
     ]] },

   { 100, 100,  [[
           -- bigroundpath
           gc:path{ radius=20, {10,10}, {40,10} }
           gc:path{ radius=20, {60,10}, {90,10}, {90,40} }
           gc:path{ radius=20, {10,50}, {10,30}, {50,30}, {50,70}, {90,70}, {90,90}, {10,90}}
     ]] },

   { 80, 40, [[
           -- Individual corner rounding (two-sided case)
           gc:path{ {10, 10}, {30, 10, flags=""}, {30,30}, radius=12 }
           gc:path{ {50, 10}, {70, 10, flags="r"}, {70,30}, radius=12 }
     ]]},

   { 80, 40, [[
           -- Individual corner rounding (two-sided case with adjoinment)
           gc:path{ {10, 10}, {30, 10, flags="r"}, {30,30,flags="r"}, {50,30,flags="r"}, {50,10}, radius=12 }
     ]]},

   { 80, 80, [[
           -- Individual corner rounding (two-sided case)
           gc:path{ {10,10}, {30,10,flags="" }, {30,30,flags="" }, {10,30}, radius=12 }
           gc:path{ {50,10}, {70,10,flags="r"}, {70,30,flags="" }, {50,30}, radius=12 }
           gc:path{ {10,50}, {30,50,flags="" }, {30,70,flags="r"}, {10,70}, radius=12 }
           gc:path{ {50,50}, {70,50,flags="r"}, {70,70,flags="r"}, {50,70}, radius=12 }
     ]]},

   { 50, 50,  [[
           -- fractional changes to left/top should not move right/bottom edge
           for y = 0, 40, 10 do
              gc:path{ {15,y+3},      {15,y+1}, {18,y+1}, lineWidth=1, color="#000" }
              gc:path{ {12+y/80,y+7}, {15,y+7}, {15,y+5}, lineWidth=1, color="#000" }
              gc:path{ {33,y+4},      {31,y+4}, {31,y+7}, lineWidth=1, color="#000" }
              gc:path{ {37,y+1+y/80}, {37,y+4}, {35,y+4}, lineWidth=1, color="#000" }
           end
     ]] },
}


-- debug: draw grid & make graphics semi-transparent
-- relies only on FillRect
local function drawGrid(gc,dx,dy,lw)
   local fcSav = gc.fillColor
   local w,h = gc.width, gc.height
   gc.fillColor = "#f2e2c8"
   local clr2 = "#e4d0b8"

   for x = 0, w, dx do
      gc:fillRect(x-lw/2, 0, lw/2, h)
      gc:fillRect(x, 0, lw/2, h, clr2)
   end
   for y = 0, h, dy do
      --gc:fillRect(0, y-lw/2, w, lw)
      gc:fillRect(0, y-lw/2, w, lw/2)
      gc:fillRect(0, y, w, lw/2, clr2)
   end

   gc.fillColor = fcSav
end


local template = [[
<!DOCTYPE HTML>
<html>
<body style='font: 11px Arial'>
<style>
.diagram:hover {
  background-color: white;
  height: 900px;
  -webkit-transform:scale(4);
  -webkit-transform-origin: 0 0;
  -webkit-transition: -webkit-transform 0.25s linear;
}
</style>
RESULTS
</body></html>
]]

-- Execute all snippets matching codePat
--
local function runSnippets(codePat, filename)
   local outcss

   local results = {}
   local function out(str)
      table.insert(results, str)
   end

   out "<table cellspacing=10>"
   for _,t in ipairs(snippets) do
      local w, h, code = t[1], t[2], t[3]

      if code:match(codePat) then

         local gc = Html2D:new(w,h)
         drawGrid(gc, 10, 10, 2)
         gc.lineWidth = 10

         -- NOTE: Gecko (Firefox) doesn't seem to support rgba(), WebKit does
         gc.fillColor = "rgba(0,0,80,0.3)"
         gc.strokeColor = "rgba(0,70,0,0.25)"

         local f = assert(load(code, nil, nil, {gc = gc, math=math} ))
         f()

         local html, css = gc:genHTML()
         if css and css ~= outcss then
            outcss = css
            out("<style>" .. css .. "</style>")
         end
         out "<tr><td>"
         out ( html )
         out "</td><td>"

         local pre = code:match("^ *")
         local str = code:gsub("^"..pre, ""):gsub("\n"..pre, "\n"):gsub("\n* *$", "")

         out ( "<pre>"..str.."</pre>" )
         out "</td></tr>\n\n"
      end
   end
   out "</table>"

   -- write all results to an HTML file

   local f = assert( io.open(filename, "wb") )


   f:write( (template:gsub("RESULTS", table.concat(results, "\n"))) )
   f:close()
   print("html2d_q: wrote file: " .. filename )
end


local filename = os.getenv("HTML2D_OUT") or ""
if filename ~= "" then
   local codePat = os.getenv("html2d_snippet")
   runSnippets(codePat or ".", filename)
end

