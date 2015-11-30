-- html2d: render 2D graphics into HTML
--
-- The Html2D class is loosely modeled after the 2D graphics context
-- interface for the HTML5 <canvas> element.  Some methods match the CANVAS
-- equivalents closely, some methods are completely new (tailored to the
-- limitations of HTML/CSS) and most functionality is not implemented.  A
-- prevalent limitation is that lines and rectangles must have horizontal
-- and veritcal edges.  Diagonal lines and non-plumb rectangles are not
-- supported, with the notable exceptions of arrows and rounded corners for
-- rectangles.
--

local Object = require "object"
local doctree = require "doctree"
local opairs = require "opairs"

local E, TYPE = doctree.E, doctree.TYPE

local sprintf = string.format

local htmlSubs = {
   ["<"] = "&lt;",
   [">"] = "&gt;",
   ["&"] = "&amp;",
   ['"'] = "&quot;"
}

local function htmlEscapeStr(str)
   return (str:gsub("[<>&]", htmlSubs))
end

local function htmlQuoteAttr(a)
   if not a:match("^%a%w*$") then
      a = '"'..htmlEscapeStr(a)..'"'
   end
   return a
end

local function htmlEscape(node)
   if type(node) == "string" then
      return htmlEscapeStr(node)
   end
   local o = setmetatable({}, {__call=table.insert})
   if node[TYPE] then
      o("<"..node[TYPE])
      for k,v in opairs(node or {}) do
         if type(k) == "string" and k:sub(1,1) ~= "_" then
            o(" "..k.."="..htmlQuoteAttr(v))
         end
      end
      o(">")
   end
   for _,v in ipairs(node) do
      o(htmlEscape(v))
   end
   if node[TYPE] then
      o("</"..node[TYPE]..">")
   end
   return table.concat(o)
end

local function xor(a,b)
   return (not a and b) or (not b and a)
end


local function range(a,b)
   local lower = math.min(a,b)
   return lower, math.max(a,b)-lower
end


----------------------------------------------------------------
-- Point datatype (complex numbers)
----------------------------------------------------------------

local mtPoint = {}
mtPoint.__index = mtPoint

local function Point(x,y)
   return setmetatable(y and {x,y} or x or {}, mtPoint)
end


-- Mulitply point by point or number.  point*point = complex multiplication,
-- which can be thought of as scaling and/or rotating a vector, where
-- p[1] = scalar factor and p[2] = imaginary
--
--    b[1] = normal scalar factor
--    b[2] = imaginary (rotated) factor
--
function mtPoint.__mul(a, b)
   if type(a) == "number" then
      a,b = b,a
   end
   if type(b) == "number" then
      return Point(a[1]*b, a[2]*b)
   end
   local x, y = b[1], b[2]
   return Point( a[1]*x - a[2]*y, a[2]*x + a[1]*y )
end

local function unpackArg(x)
    if type(x) == "table" then
      return x[1], x[2]
    else
      return x, 0
    end
end

-- Divide a point by a number or point.  point/point = complex division.
-- Using division to compare two vectors, v1/v2, can be thought of as
-- expressing v1 in terms of v2-space (the space where v2 is the unit vector
-- {1,0}).  The real and imaginary (first and second) components then
-- describe relative directions:
--
--   y==0  => the vectors are parallel, and x gives the relative scale
--   x==0  => the vectors are perpendicular, and y gives the relative scale
--
function mtPoint.__div(p, q)
   local a, b = unpackArg(p)
   local c, d = unpackArg(q)
   local x = c*c + d*d
   return Point((a*c+b*d)/x, (b*c-a*d)/x)
end


function mtPoint.__add(p,q)
   return Point(p[1]+q[1], p[2]+q[2])
end


function mtPoint.__sub(p,q)
   return Point(p[1]-q[1], p[2]-q[2])
end


function mtPoint.__eq(a,b)
   return a[1] == b[1] and a[2] == b[2]
end


function mtPoint:__tostring()
   return "("..self[1]..","..self[2]..")"
end


----------------------------------------------------------------
-- CSS
----------------------------------------------------------------


local CSS = Object:new()

function CSS:f(...)
   local prop = sprintf(...):gsub(";+$","")
   if prop ~= "" then
      table.insert(self, prop)
   end
   return prop
end

function CSS:string()
   self[1] = table.concat(self, ";")
   for n = 2, #self do self[n] = nil end
   return self[1]
end

function CSS:border(style, color, width)
   style = style or "solid"
   color = color or "default"

   if style ~= "solid" and color ~= "default" and width then
      self:f("border:%spx %s %s", width, style, color)
      return
   end

   if style ~= "solid" then
      self:f("border-style:%s", style)
   end
   if color ~= "default" then
      self:f("border-color:%s", color)
   end
   if width then
      self:f("border-width:%spx", width)
   end
end


function CSS:radius(r)
   if r and r > 0 then
      r = math.floor(r)
      self:f("-webkit-border-radius:%dpx", r)
      self:f("-moz-border-radius:%dpx", r)
      self:f("border-radius:%dpx", r)         -- Prince
   end
end


--  tb = "top" or "bottom"
--  lr = "left" or "right"
function CSS:radiusCorner(r, lr, tb)
   r = math.floor(r)
   self:f("-webkit-border-%s-%s-radius:%dpx", tb, lr, r)
   self:f("-moz-border-radius-%s%s:%dpx;", tb, lr, r)
   self:f("border-%s-%s-radius:%dpx", tb, lr, r)
end


----------------------------------------------------------------
-- GC : Graphics Context
----------------------------------------------------------------
--
-- CSS positioning
-- ---------------
--
--    box           = margin + border + content   (outer to inner)
--    top, left     = position of MARGIN
--    bottom, right = distance from MARGIN to bottom/right of parent
--                    [*not* same coordinate system as top & left]
--    width, height = width of CONTENT
--
-- We specify the top/left and bottom/right of each box, since it removes
-- border and padding from the size equation, but then we have to deal with
-- bottom/right and top/left being relative to the parent's bottom/left
-- coordinate (annoying, but doable).
--
-- Html2D uses 'px' units when positioning.
--
-- Rounding problems with Path() and FillRect():
-- ---------------------------------------------
--
-- Browsers round border positions and sizes to individual pixel sizes
-- (physical pixels, not CSS pixels) before rendering.  If we did not take
-- this into consideration, the right or bottom edges of connecting line
-- segments would often look misaligned by one pixel, even when the "right"
-- and "bottom" CSS properties of the DIV's are specified identically.  This
-- is because Path & FillRect draw with borders and the border is positioned
-- relative to left/top and rounded independently of left/top, so the
-- position of the left side influences where the right border will land
-- even when using "right" and "bottom" for placement.
--
-- We do two things to mitigate this problem:
--
--   1. All points in a path are rounded so that borders will fall at integral
--      CSS pixel boundaries.  This avoids the misalignment problem for the
--      default zoom level in most browsers, where one CSS pixel == one
--      physical pixel, but not for other non-integral multiples of zoom
--      (Alt +/-).
--
--   2. For straight line segments in a path, the background is set to the
--      border color.  The background will cover any gap between the
--      right/bottom edge and the border, if the border was rounded down.
--      This avoids misalignment but produces unpredictable line widths for
--      non-integral zoom factors.  Mis-alignment is the uglier flaw,
--      especially when zooming "in" (enlarging).
--
-- Borders
-- -------
--
-- Rendering functions assume that the active CSS stylesheet must include
-- the rules in `html2dStyle`, which is returned along with the generated
-- HTML from GenHTML().
--
----------------------------------------------------------------


local GC = Object:new()

-- Initialize GC:  w,h = size of canvas in pixel units (CSS 'px')
--
function GC:initialize(w,h)
   self.out = {}
   self.iprops = {}     -- properties inherited from parent DIV

   self.pxi = function (x) return math.floor(x+0.5) end      -- round to integral numbers of pixels
   self.canvasClass = "content"

   -- properties
   self.fillColor = "#000"
   self.strokeColor = "default"      --  'default' => CSS/HTML
   self.bgColor = "#fff"
   self.lineWidth = 2
   self.arrowLength = 9
   self.arrowWidth = 6
   self.fontSize = 14
   self.lineHeight = 16
   self.width = w
   self.height = h

   self.mtOpts = {}
   function self.mtOpts.__index(t, k)
      return t._opts[k] or self[k]
   end
end

function GC:round(x)
   return self.pxi and self.pxi(x) or x
end

function GC:round2(x)
   return self:round(x*2)/2
end

function GC:opts(opts)
   assert(opts)
   return setmetatable({_opts = opts}, self.mtOpts)
end

function GC:setSize(w,h)
   self.width = self:round(w)
   self.height = self:round(h)
end


-- Apply an inherited property to an element.  This may either add the
-- property to the canvas element or add it to the current css object for
-- the element, or find that the requested value is already being inherited.
--
function GC:iProp(css, name, ...)
   local value = sprintf(...)
   local i = self.iprops[name]
   if not i then
      self.iprops[name] = value
   elseif i ~= value then
      css:f("%s:%s", name, value)
   end
end


-- Block: generate a CSS block at (x,y) with width (w,h).  "Width" here
-- refers to total width, not the internal or "content width" of CSS.
--
-- This assumes "position:absolute" is set in document's style sheet for
-- ".html2d *"
--
function GC:block(x,y,w,h,css,txt,o)
   css:f("left:%spx", x)
   css:f("top:%spx", y)

   if w > 0 then css:f("right:%spx", self.width - x - w) end
   if h > 0 then css:f("bottom:%spx", self.height - y - h) end

   if not txt and h < self.lineHeight then
      -- In some verisons of IE, line-height will place a minimum on box
      -- height.  We do not use IProp because that would modify the parent
      -- DIV and require setting line-height for many DIVs.
      css:f("%s", "line-height:0")
   end

   local cls = o and o.class and " class="..htmlQuoteAttr(o.class)
   local html = sprintf('<div%s style="%s">%s</div>\n',
                        cls or "", css:string(), txt or "")
   table.insert(self.out, html)
end


function GC:strokeX(x, y, w, clr)
   local css = CSS:new()

   local lh = self:round(w*3)
   css:f("font:%spx Verdana, Arial", lh)
   css:f("line-height:%spx", lh)
   css:f("color:%s", clr or self.fillColor)

   if self.pxi then
      x, y = self:round(x-lh/3), self:round(y - lh/2.2)
   end
   self:block(x+0.5, y-3, 0, 0, css, "x")
--[==[

   x, y = self:round(x), self:round(y)
   clr = clr or self.fillColor

   local css = CSS:new()
   css:f("background-color:%s", clr)
   self:block(x-w, y-w, w*2, w*2, css)

   local css = CSS:new()
   css:f("border:%spx solid transparent", w-2)
   css:f("border-top-color:white;border-bottom-color:white")
   self:block(x-w+2, y-w, w*2-4, w*2, css)

   local css = CSS:new()
   css:f("border:%spx solid transparent", w-2)
   css:f("border-left-color:white;border-right-color:white")
   self:block(x-w, y-w+2, w*2, w*2-4, css)
--]==]
end


function GC:emitHTML(...)
   table.insert(self.out, sprintf(...))
end


-- Wedge: Fill a triangle with a vertical or horizontal edge.
--
--   x,y  = the 'tip' of the wedge
--   len  = distance from tip to vertical edge (negative => down or right-pointing)
--   a,d  = ascent/descent above/below the top
--   flip = Swap x/y components of len/a/d to create up/down-pointing wedge
--          This reflects the wedge across x==y, but does affect positioning
--          (the 'tip' will still be an an x,y untranslated).
--   color = color to draw wedge (default = strokeColor)
--
function GC:wedge(x, y, len, a, d, flip, color)
   local x2, y2 = self:round2(x+len), self:round2(y+a+d)
   x, y, a = self:round2(x), self:round2(y), self:round2(a)
   d = self:round2(y2 - y - a)
   len = self:round2(x2 - x)
   color = color or self.strokeColor

   local t, r, b, l = {a}, {math.abs(len), true}, {d}, {0}

   if len < 0                then r, l = l, r end
   if flip                   then t, r, b, l = l, b, r, t end

   local css = CSS:new()

   if color == "default" then
      -- allow CSS border-color to apply
      for k,v in opairs{ top=t, right=r, bottom=b, left=l } do
         if v[2] then
            css:f("border-%s-width: %spx", k, v[1], color)
         elseif v[1] ~= 0 then
            css:f("border-%s: %spx solid transparent", k, v[1])
         end
      end
   else
      -- specify color
      css:f("border:%spx solid transparent", a)
      for k,v in opairs{ top=t, right=r, bottom=b, left=l } do
         if v[2] then
            css:f("border-%s: %dpx solid %s", k, math.floor(v[1]), color)
         elseif v[1] ~= a then
            css:f("border-%s-width: %spx", k, v[1])
         end
      end
   end

   self:block(x - l[1],  y - t[1], 0, 0, css)
end


local function corner(x, y, pt)
   local lr = pt[1] > x and "right" or "left"
   local tb = pt[2] > y and "bottom" or "top"
   return lr, tb
end


local function setRadius(css, x, y, radius)
   if type(radius) == "table" then
      for _,p in ipairs(radius) do
         css:radiusCorner(radius.value, corner(x,y,p))
      end
   else
      css:radius(radius)
   end
end


-- Stroke and/or fill a rectangle.  This combines StrokeRect() and
-- FillRect() and DrawText() into one function so it can be more efficiently
-- rendered in HTML.
--
-- Note: The border is centered about the rectangle edges, as in 2D graphics
-- packages, not as in CSS.  Here, width is measured from the centers of the
-- borders.
--
-- opts = table that can be used override gc properties for the scope of
--          this operation.
--
--  Property     Description                 Default
--  -----------  --------------------------  ----------------
--  strokeStyle  style for border/stroke     false (no border)
--  strokeColor  color for outline           "default" (HTML/CSS defined)
--  lineWidth    width of line               0
--  fill         if true, fill background
--  fillColor    color for background
--  radius       radius for round corners    no rounding
--  shadow       true for shadow             no shadow
--  text         text to place in box        no shadow
--  textAlign    left, right, center         center
--  lineHeight   line height (spacing)       self.lineHeight
--
-- TODO: fontSize not inherited from gc... why?
--
function GC:rect(x,y,w,h,opts)
   local o = self:opts(opts)
   local p = self:round(o.lineWidth)
   local r = tonumber(o.radius)
   local css = CSS:new()
   local internalHeight = h
   local html

   setRadius(css, x, y, o.radius)

   -- calculate border size
   local ss = o.strokeStyle
   if ss and ss ~= "transparent" and p > 0 then
      local c = o.strokeColor
      x, y, w, h = x-p/2, y-p/2, w+p, h+p
      internalHeight = internalHeight - p

      if c ~= "default" and ss ~= "default" then
         css:f("border:%spx %s %s", p, o.strokeStyle or "solid", c)
      else
         css:f("border-width:%spx", p)
         if ss ~= "default" then
            css:f("border-style:%s", ss)
         end
         if c ~= "default" then
            css:f("border-color:%s", c)
         end
      end

      for _,b in ipairs(o.omitBorders or {}) do
         css:f("border-%s:0", b)
      end
   else
      p = 0
   end

   -- place borders on even pixel boundaries to avoid ugly misalignments due
   -- to browser rounding
   local x2, y2 = self:round(x+w), self:round(y+h)
   x, y = self:round(x), self:round(y)
   w, h = x2-x, y2-y

   if o.fill then
      css:f("background-color:%s", o.fillColor)
   end

   if o.shadow then
      css:f("-webkit-box-shadow: 2px 2px 4px #888")
      css:f("-moz-box-shadow: 2px 2px 4px #888")
   end

   if o.text and o.text ~= "" then
      local cntBR
      html = htmlEscape(o.text or ""):gsub("\n$", "")
      self:iProp(css, "white-space", "nowrap")
      html, cntBR = html:gsub("\n", "<br>")

      if o.textColor then
         css:f("color:%s", o.textColor)
      end
      if o.textAlign ~= "left" then
         css:f("text-align:%s", o.textAlign or "center")
      end
      if o.fontSize then
         self:iProp(css, "font-size", "%spx", o.fontSize)
      end

      if o.textBG then
         html = sprintf('<span style="background-color:%s">%s</span>',
                    o.textBG, html)
      end

      local lh = o.lineHeight
      self:iProp(css, "line-height", "%spx", lh)

      -- vertically align text: subtract off the line spacing in the bottom
      -- line (just a guess, but the best we can do without font metrics)
      local tp = self:round((internalHeight - (cntBR+1)*lh)/2)
      if tp > 0 then
         css:f("padding-top:%spx", tp)
      end
   end

   if o.css then
      css:f("%s", o.css)
   end

   self:block(x, y, w, h, css, html, o)
end


-- Fill a rectangle.
--
function GC:fillRect(x, y, w, h, color)
   self:rect(x, y, w, h,
             {fill=true, fillColor = color or self.fillColor, strokeStyle=false})
end


-- Add rounding to the corner identified by p
--
-- Limit radius, given two opposing opposing corners of a box.  Prince and
-- Mozilla do odd or undesirable things when border radius exceeds half of
-- the box width or height.
--
local function roundCorner(css, x, y, w, h, lw, radius, p)
   if p.round then
      local r = math.min(radius, w+lw/2, h+lw/2)
      css:radiusCorner(r, corner(x, y, p))
   end
end


-- return side that a-->b points to
--
local function sideTo(a, b)
   return a[1]<b[1] and "right" or
      a[1]>b[1] and "left" or
      a[2]<b[2] and "bottom" or
      a[2]>b[2] and "top"
end


-- Decide how much of the path can be drawn with one rectangle.  Returns up
-- to four vertices that describe up to three rectangle sides to draw.
--
-- If an input point's "round" field is set it indicates the vertex will be
-- drawn rounded (using rectangle border rounding).  In order to accommodate
-- corner rounding, the last returned vertex may stop short of the
-- corresponding input vertex.  In this case the foreshortened point will
-- have its "mid" field set.  These points should not have endcaps drawn.
-- Also, because of the potential for "mid" points, when iterating through
-- the path, the value of 'a' on the next call should be what this function
-- previously returned as the last point.
--
-- On entry:  a, b, c, d = next four points in path ("Point" objects)
-- Returns:
--     incr = number of points to consume (among b, c, d)
--     bb   = non-nil => draw A-BB
--     cc   = non-nil => draw A-BB-CC
--     dd   = non-nil => draw A-BB-CC-DD
--
local function chooseSides(a, b, c, d)
   local incr = 1
   local bb, cc, dd = b       -- returned corners

   if b==a then
      bb = nil    -- skip b
   elseif c then
      local r, i = table.unpack( (c-b)/(b-a) )
      if i == 0 then

         -- A,B,C in a line
         if r >= 0 then
            -- C extends A-B  =>  skip B (draw nothing this time)
            bb = nil
         else
            -- C reverses direction => don't draw C this time
         end

      elseif r == 0 then

         --  B--?--C?   B-C is perpendicular to A-B
         --  |             Not rounding C => draw to C.
         --  A             Rounding C     => draw to (B+C)/2
         cc, incr = c, 2
         if c.round then
            cc = (b+c)/2
            cc.mid = true
            incr = 1
         end

         --  C---?---D?       Draw three sides if D
         --  |                happens to align with A.
         --  B---A
         if d then
            local r, i = table.unpack( (c-d) / (b-a) )
            if i==0 and r >= (d.round and 2 or 1) then
               cc = c
               dd = c + (a-b)
               incr = 3
               if dd ~= d then
                  dd.mid = true
                  incr = 2
               end
            end
         end
      end
   end

   return incr, bb, cc, dd
end


-- return true if b is between a and c, inclusive
local function aligned(a,b,c)
   if a==b then
      return true
   end
   local r, i = table.unpack( (c-a)/(b-a) )
   return i==0 and r >= 1
end


--     +---,        Draw sequence of connected segments, rounding corners
--         |        where requested.  Square endcaps are drawn at endpoints,
--         `---+    with mitering at interscections.
--
function GC:path(path)
   local radius = tonumber(path.radius)
   local borderStyle = path.lineStyle or "solid"
   local color = path.color or self.strokeColor
   local lw = path.lineWidth or self.lineWidth
   local hlw = lw/2

   -- Create array of Point objects

   local pts = {}
   for _, pt in ipairs(path) do
      -- avoid misalignments due to pixel rounding in browsers
      local p = Point( self:round(pt[1] - hlw) + hlw,
                       self:round(pt[2] - hlw) + hlw )
      p.round = radius and (not pt.flags or pt.flags:match"r")
      table.insert(pts, p)
   end

   local a = pts[1]

   -- Round first/last vertex only if there is a loop.  Do this by creating
   -- a new first/last vertex between points 1 & 2 -- except when points 1,
   -- 2, and Last are already in a straight line.

   if a == pts[#pts] and a.round and not aligned(pts[#pts-1], a, pts[2]) then
      a = (a + pts[2])/2
      pts[1] = a
      table.insert(pts, a)
   end
   a.round = false
   pts[#pts].round = false

   local n = 2
   while pts[n] do

      -- decide how many sides to draw with the next rectangle

      local incr, b, c, d = chooseSides(a, pts[n], pts[n+1], pts[n+2])
      n = n + incr

      -- draw rectangle

      if b then
         local css = CSS:new()
         local oc = c or b
         local x, w = range(a[1], oc[1])
         local y, h = range(a[2], oc[2])

         -- grow[] = amount line width extends in each direction
         local grow = { top = hlw, bottom = hlw, left = hlw, right = hlw }

         css:border(borderStyle, color)

         if d then
            -- A--B--C--D : three sides, two corners
            css:f("border-width:%spx", lw)
            css:f("border-%s-width:0", sideTo(b,a))
            roundCorner(css, x, y, w, h, lw, radius, b)
            roundCorner(css, x, y, w, h, lw, radius, c)
            -- we can't clip just one endcap in a three-sided rect
            if a.mid and d.mid then grow[sideTo(b,a)] = 0 end
         elseif c then
            -- A--B--C : two sides, one corner
            -- if b is left of a or c, then draw LEFT side, else RIGHT
            css:f("border-%s-width:%spx", sideTo(a,b), lw)
            css:f("border-%s-width:%spx", sideTo(c,b), lw)
            roundCorner(css, x, y, w, h, lw, radius, b)
            -- clip endcaps when drawing to a midpoint
            if a.mid then grow[sideTo(b,a)] = 0 end
            if c.mid then grow[sideTo(b,c)] = 0 end
         else
            -- A--B : one side
            css:f("border-%s-width:%spx", w > 0 and "top" or "left", lw)
            if a.mid then grow[sideTo(b,a)] = 0 end
            if b.mid then grow[sideTo(a,b)] = 0 end
         end

         self:block(x - grow.left,
                    y - grow.top,
                    w + grow.left + grow.right,
                    h + grow.top + grow.bottom, css, nil, path)

         a = d or c or b
      end
   end
end


function GC:circle(x, y, radius, opts)
   opts = opts or {}
   local lw = opts.lineWidth or self.lineWidth
   local borderStyle = opts.strokeStyle or self.strokeStyle or "solid"
   local color = opts.strokeColor or self.strokeColor or "#000"
   local w = radius*2 + lw
   local css = CSS:new()

   css:border(borderStyle, color, lw)
   css:radius(radius+lw)
   if opts.fill then
      css:r("background-color:%s", opts.fillColor or self.fillColor)
   end
   self:block(self:round2(x-radius-lw/2), self:round2(y-radius-lw/2), w, w, css)
end


-- Draw arrowhead in different styles
--
-- o = options:
--       o.arrowLength
--       o.arrowWidth
--       o.lineWidth
--       o.open     => not filled
--       o.noTop    => only draw bottom half
--       o.noBottom => only draw top half
--
-- Draw arrow at pt, pointing *from* ptFrom.  Set back pt enough so that the
-- endpoint of the line will not extend past the sloped edge of the
-- arrow. The return value is the amount per pixel of line width to add to
-- the x offset.
--
function GC:arrow(pt, ptFrom, o)
   o = o or {}
   local x, y = table.unpack(pt)
   local xmul = pt[1]<ptFrom[1] and 1 or -1
   local len = o.arrowLength or self.arrowLength
   local wid = o.arrowWidth or self.arrowWidth
   local lw = o.lineWidth or self.lineWidth
   len = len * xmul

   if self.pxi then
      -- compensate for ordinary line rounding to even pixels; arrow tip
      -- ordinarily aligns to middle of line
      y = self.pxi(y) + 0.5
   end

   local a = wid/2
   local wa = o.noTop and 0 or a
   local wd = o.noBottom and 0 or a
   local setback = (xmul+len/a)/2

   self:wedge(x, y, len, wa, wd, nil, o.color)
   if o.open then
      local dx = math.floor(lw * math.sqrt(1 + (len*len)/(a*a)) + 0.5) * xmul
      if math.abs(dx) > 2 then
         local waNew = math.floor(wa * (len-dx+xmul)/len + 0.5)
         local r = waNew / wa
         len, wa, wd = len*r, wa*r, wd*r
      end
      self:wedge(x+dx, y, len, wa, wd, nil, o.bgcolor or self.bgColor)
   end
   local adj = (o.noTop or o.noBottom) and xmul/2 or setback
   pt[1] = pt[1] + adj * lw
   return adj
end


function GC:fillText(x,y,txt)
   local css = CSS:new()

   self:iProp(css, "font-size", "%spx", self.fontSize)
   self:iProp(css, "line-height", "%spx", self.lineHeight)
   self:iProp(css, "color", "%s", self.fillColor)
   self:iProp(css, "white-space", "nowrap")

   if self.pxi then
      x, y = self:round(x), self:round(y)
   end
   self:block(x, y, 0, 0, css, htmlEscape(txt))
end


-- These style elements are assumed by the Html2D rendering functions
--
local html2dStyle = [[
.html2d { position: relative; }
.html2d div { position: absolute; border-width: 0; border-style: solid; }
.html2d div div { position: absolute; border-width: 0; border-style: solid; }
]]

-- .html2d { position: relative; }
-- .html2d div { position: absolute; border-width: 0; border-style: solid; }
-- .html2d div.wrap { position:static; }

function GC:genHTML(props)
   -- outer DIV provides height for document flow
   -- inner DIV must be positioned to anchor child DIVs

   if not (self.width and self.height) then return "" end

   local css = CSS:new()
   css:f("width:%spx", self.width)
   css:f("height:%spx", self.height)
   for k,v in opairs(self.iprops) do
      css:f("%s:%s", k, v)
   end
   css:f("%s", props or '')

   local diagramStyle = ""
   if self.float then
      diagramStyle = sprintf(' style="float:%s"', self.float)
   end

   local class = table.concat({"html2d", self.canvasClass}, " ")
   local divs =
      '<div class=diagram'..diagramStyle..'>\n' ..
      '<div class=' .. htmlQuoteAttr(class) .. ' style="' .. css:string() .. '">\n'

   local html = divs .. table.concat(self.out, "") .. "</div>\n</div>\n"

   return html, html2dStyle
end


function GC:genTree(...)
   local html, css = self:genHTML(...)
   return { E._html{html}, E.head{ E.style{ _once="html2d", type="text/css", css } } }
end


GC.htmlEscape = htmlEscape


return GC
