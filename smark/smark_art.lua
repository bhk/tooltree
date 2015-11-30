-- smark_art.lua : ASCII graphics macro for Smark
--
-- The following character sequences are converted into 2D graphics when
-- they occur consecutively in horizontal or vertical lines:
--
--    Horizontal:      -  .  <     >  o +  ,  `
--    Vertical:        |  :  v  V  ^  o +  ,  `
--
-- Dashed lines can be constructed with "." or ":".
--
-- "<", ">", "v", "V", and "^" represent arrow heads.  When adjacent to and
-- pointing at a "+" connector, the line is extended to the middle of the
-- character cell occupied by the "+".  [ Should arrows / lines extend
-- beyond their cell always, or when adjacent to "|"? ]
--
-- "o" represents a socket (circle).  It is recognized as graphics only when
-- one of "-.|:" connect to it.
--
-- "+", "," and "`" connect both vertically and horizontally and thereby can
-- designate intersections or connecting points.  However, "," does not
-- connect upwards, and "`" does not connect downwards.  This allows finer
-- control over connections when graphics are closely spaced vertically.
--
-- Solitary instances of these characters are generally left as text, but
-- a single "|" is drawn as a (short) vertical line.
--
-- Lines consisting only of "." must be at least four characters long.  This
-- avoids converting ellipsis to a dashed line.  [Perhaps a different rule
-- would be better: "." and ":" cannot solely constitute a line? Unless
-- adjacent to other line characters (e.g. |...|)? ]

local smarkmisc = require "smarkmisc"
local memoize = require "memoize"
local opairs = require "opairs"

local rtrim = smarkmisc.rtrim

local unpack = table.unpack or unpack -- Lua 5.1 compat

local bdebug = os.getenv("SmarkArtDebug")


local function AutoTable()
   return memoize.newTable(function () return {} end)
end

-- reverse an array (in place)
--
local function reverse(a)
   local min, max = 1, #a
   while min < max do
      a[min], a[max] = a[max], a[min]
      min, max = min+1, max-1
   end
   return a
end

local function clone(t)
   local r = {}
   for k,v in pairs(t) do
      r[k] = v
   end
   return r
end

local function minmax(a,b)
   if a>b then a,b = b,a end
   return a,b
end


local function sign(a)
   return a>0 and 1 or a<0 and -1 or 0
end

-- Return "direction from a to b" as two values: x, y
local function xyDir(a,b)
   return sign(b[1]-a[1]), sign(b[2]-a[2])
end


----------------------------------------------------------------
-- Line recognition
--
-- encodeLine() recognizes lines in a string of ASCII text.  It is called
-- for with horizontal and vertical line data, after the symbols have been
-- normalized into the following:
--
--    char    H   V
--     <      <   ^
--     >      >   v
--     ,          ,     connects only with following chars
--     `          `     connects only with preceding chars
--     x     `,         connects both ways, but is rounded
--     -      -   |
--     ~      ~         like "-", but does not form polygons
--     .      .   :
--     +      +   +
--     o      o   o
--
-- It returns a table of line structures:
--
--     { y, x1, x2, flags }      [swap x&y for vlines]
--
--     y  = index (zero-based) of the row of characters
--     x1 = index (zero-based) of the starting column
--     x2 = x1 + number of characters
--
--     flags is a string of:
--         a = left arrow on left
--         A = right arrow on right
--         e = extend arrow to next midpoint on left
--         E = extend arrow to next midpoint on right
--         r = rounded on left
--         R = rounded on right
--         c = left ends at middle of character cell
--         C = right ends in middle of character cell
--         o = 'o' on left
--         O = 'o' on right
--         d = dotted ("." or ":" appeared in line)
--         s = solid ("-" or "|" appeared in line)
--         l = line only (no polygon)


-- (x,y) assumes horizontal lines; swap them for vertical
--
--
local function encodeLine(tbl, x, y, txt, pos)
   local p, px = pos or 1, #txt+1

   -- break at changed in dottedness
   local pd, ps = txt:find("%.", p), txt:find("[~%-]", p)
   local pds = pd and ps and math.max(pd,ps)

   -- break after ">" or before "<"
   local aa = txt:match(">()", p)
   local ab = txt:match(".()<", p)

   -- break after "`" and before ","
   local da = txt:match("`()", p)
   local db = txt:match(".(),", p)

   -- break before/after 'o' when not beside '-'
   local o1 = txt:match("[^~%-]()o", p)
   local o2 = txt:match("o()", txt:sub(p,p+1):match"o[%-~]" and p+1 or p)

   px = math.min(aa or px, ab or px, pds or px, o1 or px, o2 or px,
                 da or px, db or px, px)

   -- examine segment from p to px-1.  Ignore single "+" or "o".

   local c1, c2 = txt:sub(p,p), txt:sub(px-1,px-1)
   if px > p+1 or string.find("-~.<>,`", c1, 1, true) then
      local f = ""

      local function setFlag(chars, a, b)
         if a and chars:find(c1, 1, true) then f = f .. a end
         if b and chars:find(c2, 1, true) then f = f .. b end
      end

      setFlag("+,`x",  "c",  "C")
      setFlag("<",     "a",  nil)
      setFlag(">",     nil,  "A")
      setFlag("x,`",   "r",  "R")
      setFlag("o",     "o",  "O")

      if c1=="<" and txt:sub(p-1,p-1)=="+" then f = f .. "e" end
      if c2==">" and txt:sub(px,px)=="+"     then f = f .. "E" end

      if pd and pd < px then f = f .. "d" end
      if ps and ps < px then f = f .. "s" end

      if (txt:find("~", p) or px) < px then f = f .. "l" end

      table.insert(tbl, {y-1, x+p-2, x+px-2, f})
   end

   if px <= #txt then
      if txt:sub(px-1,px):match("o[%-~]") then
         px = px - 1
      end
      encodeLine(tbl, x, y, txt, px)
   end
end


-- Detect horizontal lines and generate array of hline arrays
--
-- each hline = {y,x1,x2,ends}
--  y    = row, 0-based
--  x1   = first column occupied, 0-based
--  x2   = x1 + number of coulmns occupied
--  ends = flags that describe line endings or dotted
--
local function getHLines(textLines)
   local hlines = {}

   for y, line in ipairs(textLines) do
      line = line:gsub("%a%a+", function (s) return string.rep(" ", #s) end)
      -- get consecutive sequences of graphing characters
      for x,str in line:gmatch("()([-~+<>%.%,`o]+)") do
         local isG = #str > 1 and not str:match("^%.%.%.?$")
         if not isG then
            local border = line:sub(x-1,x-1)..line:sub(x+#str,x+#str)
            isG = border:match("[|:]")
         end
         if isG then
            -- "`," are round but otherwise like "+" for hlines (directionless)
            encodeLine(hlines, x, y, str:gsub("[`,]", "x"), 1)
         end
      end
   end

   return hlines
end


local vtoh = {
   ['v'] = '>',
   ['V'] = '>',
   ['^'] = '<',
   ['|'] = '-',
   ['+'] = '+',
   [':'] = '.',
   [','] = ',',
   ['`'] = '`'
}


-- detect and encode vertical lines, returning array of vline structures
-- vline = hline with x's and y's swapped
--
local function getVLines(textLines)
   local vlines = {}

   -- extract vline characters into arrays
   --   columns[ncol][nrow] = string of chars ending at (ncol,nrow)
   local columns = AutoTable()
   for nrow, line in ipairs(textLines) do
      for ncol,ch in line:gmatch("()([%+|:vV^,`o])") do
         local alpha = line:sub(ncol-1,ncol+1):match("[a-zA-Z]?[ovV,][a-zA-Z]?")
         if not (alpha and #alpha > 1) then
            local col = columns[ncol]
            if col[nrow-1] then
               ch = col[nrow-1] .. ch    -- merge with preceding row
               col[nrow-1] = nil
            end
            col[nrow] = ch
         end
      end
   end

   for x, col in opairs(columns) do
      for y, str in opairs(col) do
         if #str > 1 or str == "|" then
            encodeLine(vlines, y-#str+1, x, str:gsub(".", vtoh), 1)
         end
      end
   end

   return vlines
end


-- ================================================================
-- getPaths


local function ptEQ(a,b)
   return a[1]==b[1] and a[2]==b[2]
end


-- From line flags, get path flags and point flags.
-- Returns: path, left/top, right/bottom
--
local function splitLineFlags(flags)
   local fp = flags:gsub("[^dsl]", "")
   local fr = flags:gsub("[^ERAOC]", ""):lower()
   local fl = flags:gsub("[^eraoc]", "")
   return fp, fl, fr
end

-- don't merge dotted with solid
local function cannotMerge(pa,pb)
   local s = pa.flags..pb.flags
   return s:match("d") and s:match("s")
end


local function catUnique(a,b)
   return a .. b:gsub(".", function (c) return a:find(c,1,true) and "" or c end)
end


-- Construct paths (arrays of points) from lines.  Each line forms at least
-- one two-point path.  When endpoints of two lines meet at a connecting
-- character ("+", ",", "`") they wil be combined into one longer path.
--
local function getPaths(hl, vl)
   -- This tracks the paths touching each (x,y) connecting point
   local xyToPath = AutoTable()
   local pathSeen = {}  -- path -> true

   -- Merge a new path with any existing path connecting with (x,y), or make
   -- this path the new path for (x,y)
   --
   local function mergePaths(pa, x, y)
      local pb = xyToPath[x][y]
      if pa == pb then
         pa.loop = true
         return pa
      elseif not pb then
         xyToPath[x][y] = pa
         return pa
      elseif cannotMerge(pa,pb) then
         return pa
      end

      -- merge pb into pa
      pathSeen[pb] = nil
      if not ptEQ({x,y}, pa[#pa]) then reverse(pa) end
      if not ptEQ({x,y}, pb[1])   then reverse(pb) end
      for n = 2, #pb do
         table.insert(pa, pb[n])
      end

      -- if pa is dotted/solid agnostic, take on pb's dotted/solid-ness
      pa.flags = catUnique(pa.flags, pb.flags)

      -- update xyToPath[] : move pb members to pa
      for _, pt in ipairs(pb) do
         xyToPath[pt[1]][pt[2]] = pa
      end

      return pa
   end

   -- Create a path with literal x,y from a line and merge with adjoining
   -- paths.
   --
   -- Horizontal lines are centered verically within their cells.  Vertical
   -- lines are centered horizontally in their cells.  Most characters ("-",
   -- "|") span the width of their cell, but "+" endings stop at the
   -- midpoint of the cell.
   --
   local function addPath(line, vert)
      local y, x1, x2, f = unpack(line)
      local cl, cr = f:match"c", f:match"C"   -- connects to left or right
      y = y + 0.5
      if cl then
         x1 = x1 + 0.5
      end
      if cr then
         x2 = x2 - 0.5
      end
      local y1, y2 = y, y
      if vert then
         x1, y1, x2, y2 = y1, x1, y2, x2
      end
      local p = { {x1,y1}, {x2,y2} }

      -- this can happen with a solitary "`".  Ignore here if it gets through.
      if x1==x2 and y1==y2 then return end

      p.flags, p[1].flags, p[2].flags = splitLineFlags(f)

      -- Avoid merging lines without connectors.  In the ">---" case we have
      -- two lines that meet perfectly but need to exist as separate paths.

      pathSeen[p] = true
      if cl then p = mergePaths(p, x1, y1) end     -- connects to left/top
      if cr then mergePaths(p, x2, y2) end         -- connects to right/bottom
   end

   -- visit all lines
   for _, line in ipairs(hl) do
      addPath(line)
   end
   for _, line in ipairs(vl) do
      addPath(line, true)
   end

   local paths = {}
   for p in opairs(pathSeen) do
      paths[#paths+1] = p
   end
   return paths
end


-- Shapes
--
-- Each path that loops, and does *not* cross its own path, decribes a shape
-- (polygon).
--
--   +---+
--   |   |   +---+
--   +-+ +---+   |
--     |   +-----+
--     +---+
--
-- Each shape is decomposed into a set of rectangles, similarly to how one
-- can be reduced to scanlines for rasterization.  Proper rendering of
-- effects and borders involves staged rendering in order to properly layer
-- the rectangle decorations.
--
--   1. Draw shadows for all component rectangles.  Borders and background
--      may also be drawn.  For simplicity, "class=rect" is used.
--
--   2. Draw background for all component rectangles.  This stage erases
--      shadows drawn within the bounds of other rectangles.  This is done
--      by setting "class=nofx" (so style sheets can disable effects)
--      and explicitly making borders transparent for each DIV.
--
--   3. Stroke path.
--
-- Outward-pointing (convex) corners of the component rectangles must be
-- rounded or not as indicated in each point's flags.
--
-- Inward-pointing corners, and any completely internal corners, would
-- ideally be drawn non-rounded to avoid gaps in the background.  However,
-- due to the fact that borders overlay the background and that adjacent
-- rectangles overlap their borders, the width of the borders provides a
-- fudge factor that makes this unnecessary as long as border radius does
-- not get too large.  As shown below, even when rect A and rect B are drawn
-- with a border radius, the background & border to A and B will still
-- cover the gap.
--
-- .                              ####     "#" = path (shape boundary)
-- .                              ####     "-" = covered by A's border
-- .        internal rect A       ####     "|" = covered by B's border
-- .                             -#####    "+" = covered by A & B borders
-- .     #################----++++++###############
-- .     ###################++++++||||#############
-- .                     #####|
-- .         outside      ####    internal rect B
-- .                      ####
--
-- Shapes may intersect with other shapes.  In order to render shapes with
-- backgrounds or shadow effects without obscuring the borders of
-- intersecting shapes, we group crossed shapes together so they can be
-- rendered in the same visual plane -- essentially as one larger shape, but
-- with some internal lines.  We do this by interleaving their rendering
-- stages.  For each plane or "layer" we do the following:
--
--    1. Draw phase 1 of all shapes.
--    2. Draw phase 2 of all shapes.
--    3. Draw phase 3 of all shapes.
--
-- We can apply some optimizations to this:
--
-- * In stage 2 we can skip drawing the most recently drawn rectangle from
--   stage 1 (or any rectangle that has not been overlaid by others in stage
--   1) as long as the rectangle's background has been rendered. (Stage 1
--   would otherwise not require rendering of background.)
--
-- * In stage 3 we can skip drawing the most recently drawn rectangle from
--   stage 2 or stage 1 (or any other rect not since overlaid) as long as
--   its borders have been drawn.  (Stages 1 and 2 would otherwise not
--   require rendering of borders.)
--


-- Return true if any of A's hlines cross one of B's vlines.  "Touching"
-- does not count as crossing.
--
local function pathCrossesHV(a,b)
   local ahStart = a[1][1]~=a[2][1] and 1 or 2
   local bvStart = b[1][2]~=b[2][2] and 1 or 2

   for i = ahStart, #a-1, 2 do
      local y, x1, x2 = a[i][2], minmax(a[i][1], a[i+1][1])
      for j = bvStart, #b-1, 2 do
         local x, y1, y2 = b[j][1], minmax(b[j][2], b[j+1][2])
         if x1 < x and x2 > x and y1 < y and y2 > y then
            return true
         end
      end
   end
   return false
end


-- Construct a shape from path, or return nil is path is not suitable.
--
-- A **shape** consists of three fields:
--    rects:    an array of rectangles
--    path:     the path bounding the shape
--    origPath: the original path (incomplete in the case of an inferred shape)
--    x:        the minimum x value
--
local function makeShape(path)
   if not path.loop or pathCrossesHV(path, path) or path.flags:match('l') then
      return nil
   end

   -- Create an index of [x][y] -> points (to look up flags easily)
   local xyToPoint = AutoTable()
   for n = 1, #path do
      local p = path[n]
      xyToPoint[p[1]][p[2]] = p
   end

   -- Create sorted list of y indices for this path.  We only need to visit
   -- every other point because each hline has two points with the same y.

   local ys = {}
   local yToXs = {}
   for n = 1, #path, 2 do
      local y = path[n][2]
      if not yToXs[y] then
         yToXs[y] = {}
         ys[#ys+1] = y
      end
   end
   table.sort(ys)

   -- Find vertical lines that cross y+epsilon.  These establish the
   -- left/right boundaries below y and above the next y.

   -- nStart = start of first vertical line
   local nStart = (path[1][2] == path[2][2]) and 2 or 1
   for n = nStart, #path-1, 2 do
      local x = path[n][1]
      local y1, y2 = minmax(path[n][2], path[n+1][2])

      for _,y in ipairs(ys) do
         if y1 <= y and y2 > y then
            -- Store X coordinate along with flags IF this is at a corner
            table.insert(yToXs[y], x)
         end
      end
   end

   -- Generate list of rectangles

   local shape = {
      path = path,
      rects = {}
   }

   local sx1, sy1, sx2, sy2 = math.huge, math.huge, -math.huge, -math.huge

   local dotted = path.flags:match"d" and true

   for ny = 1, #ys-1 do
      local y1, y2 = ys[ny], ys[ny+1]
      local xs = yToXs[y1]
      table.sort(xs)
      for nx = 1, #xs, 2 do
         local x1, x2 = xs[nx], xs[nx+1]
         local rect = { x1, y1, x2-x1, y2-y1 }
         rect.dotted = dotted

         sx1 = math.min(sx1, x1)
         sy1 = math.min(sy1, y1)
         sx2 = math.max(sx2, x2)
         sy2 = math.max(sy2, y2)

         -- determine roundness for points
         local radius = {}
         radius.value = 0
         for _, x in ipairs{x1,x2} do
            for _, y in ipairs{y1, y2} do
               local p = xyToPoint[x][y]
               if not p or not p.flags:match"r" then
                  table.insert(radius, {x,y,flags=""})  -- NOT round
               end
            end
         end
         if #radius < 4 then
            -- some are rounded; non-round corners have explicit radius=0
            rect.radius = radius
         end

         table.insert(shape.rects, rect)
      end
   end

   shape.x = sx1

   return shape
end



-- Return true if a set of rectangles `rects` completely overlaps rectangle `r`
--
-- For each pair of rects, there are up to four resulting rects in the
-- difference.  These correspond to cases in the code below.
--
--     +---------+  -- y
--     |1        |
--     +--+---+--+  -- yy
--     |2 |   |3 |
--     +--+---+--+  -- y4
--     |4        |
--     +---------+  -- y2
--     |  |   |  |
--     x  xx xx2 x2
--
local function rectsCover(rects, r, ndx)
   local x, y, w, h = unpack(r)
   local x2, y2 = x+w, y+h

   local rr = rects[ndx]
   ndx = ndx + 1
   if not rr then return false end

   local xx, yy, ww, hh = unpack(rr)
   local xx2, yy2 = xx+ww, yy+hh

   if xx >= x2 or yy >= y2 or xx2 <= x or yy2 <= y then
      -- no intersection: look for other rects
      return rectsCover(rects, r, ndx)
   end

   -- #1
   if yy > y and not rectsCover(rects, {x, y, w, yy-y}, ndx) then
      return false
   end

   local y4 = math.min(yy2,y2)
   if y4 > yy then
      -- #2
      if xx > x and not rectsCover(rects, {x, yy, xx-x, y4-yy}, ndx) then
         return false
      end
      -- #3
      if xx2 < x2 and not rectsCover(rects, {xx2, yy, x2-xx, y4-yy}, ndx) then
         return false
      end
   end

   -- #4
   return y4 >= y2 or rectsCover(rects, {x, y4, w, y2-y4}, ndx)
end


-- Return true if a *contains* b entirely
--
local function shapeContains(a, b)
   for _,rb in ipairs(b.rects) do
      if not rectsCover(a.rects, rb, 1) then
         return false
      end
   end
   return true
end


-- Identify shapes in paths[], removing them from paths and returning an
-- array of shapes.
--
local function getShapes(paths)
   local shapes, others = {}, {}
   for _, path in ipairs(paths) do
      local shape = makeShape(path)
      if shape then
         shapes[#shapes+1] = shape
      else
         others[#others+1] = path
      end
   end
   return shapes, others
end


local function isOver(a, b)
   for _,ll in ipairs(b.overs or {}) do
      if a == ll then return true end
   end
   return false
end


local function shapeCrosses(a,b)
   local pa = a.origPath or a.path
   local pb = b.origPath or b.path
   return pathCrossesHV(pa, pb) or pathCrossesHV(pb, pa)
end


-- Add shape to layers[].  Shapes that intersect other shapes must occupy
-- the same layer.
--
local function addShape(layers, shape, overs)
   local oldToNew = {}
   local layer = {shape, overs=overs or {}}
   local bConflict = false

   -- Add members of ll to layer
   local function mergeLayer(ll)
      if isOver(ll, layer) or isOver(layer, ll) then
         bConflict = true   -- invalid configuration
         return
      end
      for _, s in ipairs(ll) do
         table.insert(layer, s)
      end
      for _, o in ipairs(ll.overs or {}) do
         table.insert(layer.overs, o)
      end
      oldToNew[ll] = layer
   end


   -- look for crossed (intersecting) shapes
   for _, ll in ipairs(layers) do
      local merged = false
      for _, ss in ipairs(ll) do
         if shapeCrosses(shape, ss) then
            merged = true
            mergeLayer(ll)
            break
         end
      end
      if not merged then
         if shapeContains(ll[1], shape) then
            ll.overs = ll.overs or {}
            table.insert(ll.overs, layer)
         elseif shapeContains(shape, ll[1]) then
            table.insert(layer.overs, ll)
         end
      end
   end

   if bConflict then return false end

   -- purge any removed layers, and fix references left in overs
   table.insert(layers, 1, layer)
   local nOut = 1
   for nIn = 1, #layers do
      local ll = layers[nIn]
      layers[nIn] = nil
      if not oldToNew[ll] then
         layers[nOut] = ll
         nOut = nOut+1
         for ndx = 1, ll.overs and #ll.overs or 0 do
            ll.overs[ndx] = oldToNew[ll.overs[ndx]] or ll.overs[ndx]
         end
      end
   end

   return true
end


-- A **layer** is an array of shapes, plus the following field:
--   layer.overs = an array of layers that must appear over this layer
--
local function getLayers(shapes)
   local layers = {}
   for _,s in ipairs(shapes) do
      addShape(layers, s)
   end
   return layers
end



-- Shape inference
--
-- When one vertex is missing as if obscured by other shapes, we can create
-- a shape to be displayed underneath it.  This will allow its background
-- and effects to match that of other shapes.  Shape inteference should not
-- hide any visible lines or create any new visible lines, so layering of
-- shapes is an important aspect.
--
--   +---+          B is a rectangle obscured by A.
--   | A |--+       When creating a shape for B we place it in a
--   +---+ B|       layer below A.
--     +----+
--
--     +----+
--   +---+ B|       B and C are rectangles obscured by A, and they are
--   |A  |--+--+    in the same layer; neither obscures the other.  The
--   |   |--+  |    first one made a shape will create a new layer
--   +---+     |    below A. The second must be added to the same layer.
--     |    C  |
--     +-------+
--
--      +----+
--   +--+-+ B|      A & B are in the same layer.
--   |A | |--+--+   C could be obscured by A ,but not by B,
--   |  +-+--+  |   so C cannot be inferred.
--   +----+   C |
--     +--------+
--
--      +----+
--   +--+-+ B|      A & B are in the same layer.
--   |A | |  |--+   C could be obscured by A and B.
--   |  +-+--+  |   A shape will be created for C below the A&B layer.
--   +----+   C |
--     +--------+
--
--   +-------+
--   |A+---+ |      A is below B.  C is obscured by B, not A.
--   | | B |-+--+   C must be in the same layer as A.
--   | +---+ | C|
--   |    |  |  |
--   +----+--+  |
--        +-----+
--
--   +---------+
--   |A+---+   |      C is below B and above A.
--   | | B |-+ |      The shape for C must fall in a new layer
--   | +---+C| |      between A and B.
--   |   +---+ |
--   +---------+
--


-- Return a new array of layers ordered from top to bottom: that is, no
-- layer will be preceded by an "over" layer.
--
local function sortLayers(layers)
   local o = {}
   local visited = {}
   local function visit(ary)
      for _, l in ipairs(ary) do
         if not visited[l] then
            visited[l] = true
            if l.overs then visit(l.overs) end
            table.insert(o, l)
         end
      end
   end
   visit(layers)
   return o
end


-- Returns true if line from a to b is covered by other layers of shapes.
-- Adds all covering layers to overs[]
--
local function isCovered(a, b, layers, overs, cwid, chgt)
   local dir = (a[1] == b[1]) and 2 or 1
   local runs = { { minmax(a[dir], b[dir]) } }
   local axis = a[3-dir]

   for _,layer in ipairs(sortLayers(layers)) do
      local layerIsOver = false
      for _,s in ipairs(layer) do
         for _,r in ipairs(s.rects) do
            local x, y, w, h = unpack(r)
            local x2, y2 = x+w+cwid, y+h+chgt
            x = x - cwid
            y = y - chgt

            if dir == 2 then
               x, y, x2, y2 = y, x, y2, x2
            end

            if y <= axis and axis <= y2 then
               local n = 1
               while runs[n] do
                  local r = runs[n]
                  local a,b,c,d
                  a,b = r[1], math.min(r[2],x)      -- get what's left of range
                  c,d = math.max(x2, r[1]), r[2]    -- get what's right of the range

                  if a >= b and c >= d then
                     -- nothing left
                     table.remove(runs, n)
                     layerIsOver = true
                  elseif a < b and c < d then
                     -- two runs
                     runs[n] = {c,d}
                     table.insert(runs, n, {a,b})
                     layerIsOver = true
                  else
                     -- one run
                     if c<d then a,b = c,d end
                     if a~=r[1] or b~=r[2] then
                        layerIsOver = true
                        r[1] = a
                        r[2] = b
                     end
                     n = n + 1
                  end
               end
            end
         end
      end
      if layerIsOver then
         table.insert(overs, layer)
      end
      if #runs == 0 then return true end
   end
   return false
end



-- Compute single point that would close the path:
--
--   1. First & last segments may lengthen IFF they do not end at a
--      connecting point.
--   2. IFF they end at a connecting point, they must may connect in a
--      perpendicular direction (toward the other point).
--   3. "All" of the inferred portion must be hidden by other shapes (just the
--      part under adjacent character cells).
--   4. The resulting path *with inferred portion* must not cross itself.
--
local function inferShape(path, layers, cw, ch)
   if path.loop then return end
   if #path < 3 then return end

   local decorations = path[1].flags .. path[#path].flags
   if decorations:match"[oa]" then return end

   local a, a2 = path[1], path[2]
   local b, b2 = path[#path], path[#path-1]


   -- return a description of constraints on where the next vertex might lie
   -- a = tip, b = previous point
   --    { <xcon:range>, <ycon:range>},  range :: {<min:number>, <max:number>}
   --
   local function nextVertex(a,b)
      local d = a[1]==b[1] and 2 or 1    -- axis or dimension of a->b
      local e = 3-d
      if a.flags:match"c" then
         -- invent perpendicular edge
         return { [d] = {a[d], a[d]},
                  [e] = {-math.huge, math.huge} }
      else
         -- extend edge
         return {
            [d] = a[d]>b[d] and { a[d], math.huge} or { -math.huge, a[d] },
            [e] = { a[e], a[e] }
         }
      end
   end

   local c1 = nextVertex(path[1], path[2])
   local c2 = nextVertex(path[#path], path[#path-1])

   local function rangeIntersect(a,b)
      return math.max(a[1], b[1]), math.min(a[2], b[2])
   end

   local x, xMax = rangeIntersect(c1[1], c2[1])
   local y, yMax = rangeIntersect(c1[2], c2[2])

   if x ~= xMax or y ~= yMax then
      return   -- extensions/perpendiculars do not meet at one point
   end

   local overs = {}
   if not isCovered(a, {x,y}, layers, overs, cw, ch) or
      not isCovered(b, {x,y}, layers, overs, cw, ch) then
      return  -- inferred edge portions are not covered
   end

   -- construct new path and see if it can make a shape

   local p2 = clone(path)
   local p = {x, y, flags=""}

   if p2[1].flags:match"c" then
      table.insert(p2, 1, p)
   else
      p2[1] = p
   end
   if p2[#p2].flags:match"c" then
      table.insert(p2, p)
   else
      p2[#p2] = p
   end
   p2.loop = true

   local shape = makeShape(p2)
   if shape then
      shape.origPath = path
      return shape, overs
   end
end


local function inferShapes(layers, paths, cw, ch)
   local found
   repeat
      found = false
      for n = #paths, 1, -1 do
         local shape, overs = inferShape(paths[n], layers, cw, ch)
         if shape and addShape(layers, shape, overs) then
            found = true
            table.remove(paths, n)
         end
      end
   until found == false
end


-- ================================================================
-- Drawing functions
-- ================================================================


-- Draw arrow tip at pt with tail /toward/ ptFrom
--
local function arrowAt(gc, pt, ptFrom, cwid, chgt)
   if not pt.flags:match("a") then return end

   local len = chgt * 2 / 3
   local mx, my = xyDir(pt, ptFrom)

   -- hwid is not proportionally sized (too small makes it invisible)
   local hwid = math.max(3, math.floor(1 + len / 3))   -- TODO: rounding elsewhere

   if pt.flags:match("e") then
      pt[1] = pt[1] - mx*cwid/2
      pt[2] = pt[2] - my*chgt/2
   end

   gc:wedge(pt[1], pt[2], (mx+my) * len, hwid, hwid, my~=0)
   pt[1] = pt[1] + mx*hwid
   pt[2] = pt[2] + my*hwid
end


-- Draw circle at pt, moving pt to edge of circle toward ptFrom
--
local function circleAt(gc, pt, ptFrom, cwid, chgt)
   if not pt.flags:match("o") then return end

   local r = math.floor( (cwid+chgt) / 6 )
   local lw = 2

   -- back up to center of character cell
   local mx, my = xyDir(pt, ptFrom)
   local x = pt[1] + mx*(cwid/2)
   local y = pt[2] + my*(chgt/2)

   gc:circle(x, y, r, {lineWidth=lw})

   -- shorten last segment to point to edge of circle
   pt[1] = x + mx*(r + lw/2)
   pt[2] = y + my*(r + lw/2)
end


local function drawRect(gc, rect, class, o)
   local x, y, w, h = unpack(rect)
   local class = class or "rect"
   if rect.dotted then class = "d" .. class end

   o = o or {}
   o.strokeStyle = "default"
   o.lineWidth = o.lineWidth or (rect.dotted and 2 or 3)
   o.class = class

   if rect.radius then
      o.class = o.class .. " round"
      o.radius = rect.radius
   end
   gc:rect(x, y, w, h, o)
end


local function drawPaths(gc, paths, cwid, chgt)

   -- scale paths
   for _, path in ipairs(paths) do
      for n, pt in ipairs(path) do
         path[n] = { pt[1] * cwid, pt[2] * chgt, flags = pt.flags}
         -- collect roundness flags from each point
         path.flags = path.flags .. pt.flags
      end
   end

   -- draw shapes [to replace rects/polys]
   local shapes

   shapes, paths = getShapes(paths)

   local layers = getLayers(shapes)

   inferShapes(layers, paths, cwid, chgt)

   for _, layer in ipairs(reverse(sortLayers(layers))) do
      local rects = {}
      for _, shape in ipairs(layer) do
         for _, rect in ipairs(shape.rects) do
            table.insert(rects, rect)
         end
      end

      -- 1. Draw all
      for _, rect in ipairs(rects) do
         drawRect(gc, rect, "rect")
      end

      if #rects > 1 then
         -- 2. No borders
         for _, rect in ipairs(rects) do
            drawRect(gc, rect, "nofx", {strokeColor="transparent"})
         end

         -- 3. Stroke (borders)
         for _, shape in ipairs(layer) do
            local p = shape.path
            p.class = p.flags:match("d") and "dline" or "line"
            if p.flags:match("r") then
               p.radius = cwid
            end
            p.lineWidth = 3
            gc:path(shape.path)
         end
      end
   end

   -- draw remaining paths

   for _,p in ipairs(paths) do
      p.class = p.flags:match("d") and "dline" or "line"

      if p.flags:match("r") then
         -- Rounding: gc:path() needs a number for radius.  [TODO:
         -- radius="default", which must also avoid rounding endpoints]
         p.radius = cwid     -- p.class = p.class .. " round"
      end

      arrowAt(gc, p[1], p[2], cwid, chgt)
      arrowAt(gc, p[#p], p[#p-1], cwid, chgt)
      circleAt(gc, p[1], p[2], cwid, chgt)
      circleAt(gc, p[#p], p[#p-1], cwid, chgt)

      gc:path(p)
   end
end


local function clearChars(str, a, b)
   return str:sub(1,a-1) .. string.rep("\t", b-a+1) .. str:sub(b+1)
end

-- Replace graphics characters used that were used to define lines with space.
--
local function clearLineChars(textLines, hl, vl)
   local t = {}
   for n,v in ipairs(textLines) do
      t[n] = v
   end

   -- clear hlines
   for _,line in ipairs(hl) do
      local y = line[1]+1
      t[y] = clearChars(t[y], line[2]+1, line[3])
   end

   -- clear vlines
   for _,line in ipairs(vl) do
      local x = line[1]+1
      for y = line[2]+1, line[3] do
         t[y] = clearChars(t[y], x, x)
      end
   end

   return t
end


-- Scan lines of ASCII text for graphics
-- Returning object describing rectangles, lines, and remaining text
--
--   o.hlines = array of {y, x1, x2, mask}
--   o.vlines = same as hlines, transposing x & y
--   o.rects = array of {x1, y1, x2, y2, flags}
--
-- mask = bitmask
-- flags = string of: "r" => rounded; "d" => dotted
--
local function scan(textLines)
   local o = {}

   o.rows = #textLines
   o.columns = 0
   for _,line in ipairs(textLines) do
      line = rtrim(line)
      if #line > o.columns then
         o.columns = #line
      end
   end

   local h, v, r
   h = getHLines(textLines)
   v = getVLines(textLines)
   o.txt = clearLineChars(textLines, h, v)
   o.paths = getPaths(h, v)

   return o
end


local function getRuns(g)
   local runs = {}
   local nextXTR = {}

   for nline, txt in ipairs(g.txt) do
      local xToRun =  nextXTR
      nextXTR =  {}

      local pos = 1
      while pos <= #txt do
         local a = txt:find("[^ \t]", pos)
         if not a then break end
         local b1 = txt:find("   ", a) or #txt+1
         local b2 = txt:find("\t", a) or #txt+1
         local b = math.min(b1,b2)
         local text = rtrim(txt:sub(a,b-1))

         -- find graphics on left
         local toleft
         for n = a-1, 1, -1 do
            local c = txt:sub(n,n)
            if c ~= " " then
               if c == "\t" then
                  toleft = a-n-1
               end
               break
            end
         end

         -- find graphics on right
         local toright = txt:match("^ *()\t", b)
         if toright then
            toright = toright - (a + #text)
         end

         -- close to graphics on left, right?  Graphics centered?
         local mid
         if toleft and toright and math.abs(toleft-toright) <= 1 then
            mid = a - 1 + (#text + toright - toleft)/2
         end

         local run = {
            x = a-1,
            y = nline-1,
            text = text,
            mid = mid,
            atleft = (toleft and toleft < 2) and toleft or nil,
            atright = (toright and toright < 2) and toright or nil
         }

         -- left/right aligned with run above?
         local prev = xToRun[a]
         if prev then
            prev.left = true
            run.left = true
         end
         prev = xToRun[a + #text - 1/2]
         if prev then
            prev.right = true
            run.right = true
         end
         nextXTR[a] = run
         nextXTR[a + #text - 1/2] = run

         table.insert(runs, run)
         pos = b+1
      end
   end

   return runs
end


-- debug: draw grid & make graphics semi-transparent
local function drawGrid(gc,g,lw,cwid,chgt)
   local c = gc.fillColor
   gc.fillColor = "#bbb"
   for n = 0, g.rows-1 do
      gc:fillRect(0, n * chgt, g.columns * cwid, lw)
   end
   for n = 0, g.columns - 1 do
      gc:fillRect(n*cwid, 0, lw, g.rows*chgt)
   end
   gc.fillColor = c
end


local function round(n)
  return math.floor(n*100+.05)/100
end


-- gen: Construct diagram from rect/hline/vline/txt arrays
--
local function gen(g, gc)
   local aspect    = 2.0   --  character cell height/width
   local maxWidth  = 640
   local maxEm     = 16
   local fontScale = 0.78  -- proportional between cell height and font size

   gc.canvasClass = "art"

   -- scale graph down if wider than target width
   local em = math.min(maxEm, round(maxWidth / g.columns * aspect))
   local chgt = em
   local cwid = em / aspect

   gc:setSize(g.columns * cwid, g.rows*chgt)
   gc.arrowLength = round(em * 8 / 12)
   gc.fontSize = round(em * fontScale)
   gc.lineHeight = chgt
   gc.strokeColor = "default"
   gc.strokeStyle = nil
   gc.fillColor = "black"

   if bdebug then drawGrid(gc,g,1,cwid,chgt) end

   -- rectangles & lines

   drawPaths(gc, g.paths, cwid, chgt)

   -- draw text

   local runs = getRuns(g)
   for _, r in ipairs(runs) do
      local x, y, w = r.x *cwid, r.y*chgt, #r.text * cwid
      local align
      if r.mid then
         x = r.mid*cwid - w/2
      elseif r.atleft then
         align = "left"
      elseif r.atright then
         align = "right"
      elseif r.left then
         align = "left"
      elseif r.right then
         align = "right"
      end
      if align == "right" then
         x = x-w
         w = w*2
      end
      gc:rect(x, y, w, gc.lineHeight, {text = r.text, textAlign=align})
   end
end


local function splitLines(txt)
   local lines = {}
   for line in txt:gmatch("([^\n]*)\n?") do
      table.insert(lines, line)
   end
   if lines[#lines] == "" then table.remove(lines) end
   return lines
end


local function render2D(node, gc)
   local lines = splitLines(node.text)
   return gen( scan(lines), gc )
end


return {
   render2D = render2D
}
