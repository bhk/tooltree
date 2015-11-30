-- mscgen:  Message Sequence Chart Generator
--
-- The input syntax and functionality is based on 'MscGen' [see
-- http://www.mcternan.me.uk/mscgen/ ]
--
-- Wishlist: html2d should generate doctree & accept doctree; msc will need
-- to generate {type="br"} vs. "\n"

local lpeg = require "lpeg"
local maxn = require "maxn"

----------------------------------------------------------------
-- Parsing
----------------------------------------------------------------

local parse do
   local P, R, S = lpeg.P, lpeg.R, lpeg.S
   local Cc, Cmt, Ct, Cs, Cp = lpeg.Cc, lpeg.Cmt, lpeg.Ct, lpeg.Cs, lpeg.Cp

   local comment, spaces, string, op, oppat, ident, attr, attrs,
         arc, arcgrp, arcs, entity, entities, option, options, mscbody, msc

   -- Keep track of all tokens that failed to match and their positions.  In
   -- case of failure, those longest failed match gives us the most
   -- informative error information.

   local failures
   local function wanted(s,i,c)
      if not failures[i] then
         failures[i] = {}
      end
      table.insert(failures[i], c)
   end
   local function fail(desc)
      return Cmt( Cc(desc), wanted ) * P(false)
   end

   -- constructors

   local function Attr(name, value)
      return { key=name, value=value }
   end
   -- Arc = { arc={ lpos, lhs, op, rpos, rhs }, attrs = <Attrs>, pos=<number> }
   local function Arc(arc, ...)
      local a = { attrs = {...} }
      if type(arc) == "table" then
         a.lpos, a.lhs, a.op, a.rpos, a.rhs = table.unpack(arc)
      else
         a.op = arc
      end
      return a
   end
   local function Entity(name, ...)
      return { key=name, attrs = {...} }
   end
   local function Option(a,b,c,d)
      return { kpos=a, key=b, vpos=c, value=d, }
   end
   local function MSC(a,b,c)
      return { options = a, entities = b, arcs = c }
   end


   comment   = (P"#" + P"//") * (1 - P"\n")^0 * ("\n" + -P(1))
              + P"/*" * (1 - P"*/")^0 * P"*/"

   spaces    = ( S" \t\r\n"^1 + comment )^0

   -- L = literal (optionally followed by spaces)
   -- T = token (captured literal)

   local function L(str, desc)
      return str * spaces + fail(desc or str)
   end
   local function T(str, desc)
      return L(Cs(str), desc or str)
   end

   -- construct a case-insensitive match
   local function ipat(str)
      local pat
      for c in str:gmatch(".") do
         local cpat = S(c:lower()..c:upper())
         pat = pat and (pat * cpat) or cpat
      end
      return pat
   end

   local function ci(str)
      return ipat(str) / str
   end


   -- patterns

   ident    = T( R("AZ", "az", "09", "__")^1, "identifier" )

   string   = ident + '"' * Cs( ( P"\\n" / "\n"
                                  + P"\\" / "" * S"\\'\""
                                  + (1 - P'"'))^0 ) * L'"'

   oppat    = P"<->" + "<=>" + "<.>" + "<<=>>" + "<:>" + "<<>>" +
              "->"   + ">>"  + "=>>" + "=>"    + ".>"  + ":>" +
              "<<="  + "<<"  + "<-"  + "<="    + "<."  + "<:" +
              "--"   + "=="  + ".."  + "::"    +
              ci"-x" + ci"x-" + ci"rbox" + ci"abox" + ci"box"

   op       = T(oppat, 'operator ("->", "box", ..)')

   attr     = ident * L"=" * string / Attr
   attrs    = attr * ( L"," * attr )^0

   arc      = ( T"..." + T"---" + T"|||"
                + Ct(Cp() * (string + T"*") * op * Cp() * (string + T"*")) )
              * (L"[" * attrs * L"]")^0 / Arc
   arcgrp   = Ct( arc * ( L","  * arc )^0 )
   arcs     = Ct( arcgrp * ( L";" * arcgrp )^0 ) * L";" + Ct("")

   entity   = string * ( L"[" * attrs * L"]" )^0 / Entity
   entities = Ct( entity * ( L"," * entity )^0 ) * L";" + Ct("")

   option   = Cp() * ident * L"=" * Cp() * string / Option
   options  = Ct( option * ( L"," * option )^0 * L";" + "" )

   mscbody  = options * entities * arcs
   msc      = spaces * ( (L(ipat"msc") + "") * L"{" * mscbody * L"}"
                       + mscbody ) / MSC * spaces
              * (-P(1) + fail("end of chart"))


   function parse(str, warn)
      failures = { [1] = { "identifier" } }
      local a,b = msc:match(str)
      if not a then
         local n = maxn(failures)
         warn(n, "msc: expected %s", table.concat(failures[n], " or "))
      else
         a.warn = warn
      end
      return a,b
   end
end


----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

local function sign(x)
   return x>0 and 1 or x<0 and -1 or 0
end

local function minmax(a,b)
   if a < b then return a,b else return b,a end
end

local function round(val,res)
   res = res or 1
   return math.floor(math.floor(val*res + 0.5)/res)
end

local function drawAngleBox(gc, x, y, w, h, txt, clr)
   local lw, lwSav = 2, gc.lineWidth
   gc.lineWidth = lw
   local a
   -- round everything to minimize artifacts/gaps caused by rounding in the browser
   x, y, w, h, a = round(x), round(y-lw/2), round(w), round(h+lw), round(h/4)
   x = x + a
   w = w - 2*a
   local ym = y + h/2
   local o = {open=true, color=clr, arrowLength=a, arrowWidth=h}
   local pl, pr = {x-a, ym},  {x+w+a, ym}
   gc:arrow(pl, pr, o)
   gc:arrow(pr, pl, o)

   gc:rect(x+lw/2, y+lw/2, w-lw, h-lw, {
              text = txt, fill = true, fillColor = "white",
              strokeStyle = "solid", omitBorders = {"right", "left"},
              strokeColor = clr or nil
           })

   gc.lineWidth = lwSav
end


-- This table indicates whether an operator points right-to-left, and
-- if so returns its mirror image.
--
local r2l = {
   ["<<="] = "=>>",
   ["<<"]  = ">>",
   ["<-"]  = "->",
   ["<="]  = "=>",
   ["<."]  = ".>",
   ["<:"]  = ":>",
   ["x-"]  = "-x",
}

-- This table maps operators to style tables, after r2l[] and gsub("<","")
-- have been applied to the operator's name.  The style tables follow the
-- convention for Html2D's arrow() and path() options.
--
-- Note that gc properties provide defaults for these.
--
local arcStyles = {
   ["->"]  = { open = true, noTop=true, arrowWidth=12 },
   ["=>>"] = { open = true, arrowWidth=12 },
   ["-x"]  = { open = true, noTop=true  },
   ["=>"]  = { },
   [".>"]  = { lineStyle = "dotted" },
   [">>"]  = { lineStyle = "dashed" },
   [":>"]  = { arrowLength=13, arrowWidth=10, lineStyle="double", lineWidth=3 },
}
arcStyles["--"] = arcStyles["->"]
arcStyles["=="] = arcStyles["=>"]
arcStyles[".."] = arcStyles[".>"]
arcStyles["::"] = arcStyles[":>"]


----------------------------------------------------------------
-- option/attribute typechecking
----------------------------------------------------------------


local function newType(name, f)
   return setmetatable({name}, {__index = function(t,k) return f(k) end})
end

local numeric = newType("numeric", tonumber)
local any = newType("any", function (x) return x end)

local optionTypes = {
   "option",
   arcgradient = numeric,
   entities    = {'"on" or "off"',     on="on", off="off"},
   float       = {'"left" or "right"', right="right", left="left"},
   hscale      = numeric,
   width       = numeric,
}


local attrTypes = {
   "attribute",
   arclinecolor = any,
   arcskip = numeric,
   arctextbgcolor = any,
   arctextcolor = any,
   id = any,
   idurl = any,
   label = any,
   linecolor = any,
   textbgcolor = any,
   textcolor = any,
   url = any,
}


-- Check option or attribute values and index values by normalized name
--
local function getValues(m, tbl, types)
   local options = {}
   for _, o in ipairs(tbl) do
      local key = o.key:lower():gsub("colour", "color")
      local typ = types[key]

      if not typ then
         m.warn(o.kpos, "msc: unsupported %s: %s", types[1], o.key)
      elseif options[key] then
         m.warn(o.kpos, "msc: %s appears twice: %s", types[1], o.key)
      elseif not typ[o.value] then
         m.warn(o.vpos, "msc: %s %s ignored; value should be %s",
                types[1], o.key, typ[1])
      else
         options[key] = typ[o.value]
      end
   end
   return options
end


local function makeLink(node, url)
   if url then
      if type(node) == "string" or node._type then
         node = {node}
      end
      node._type = "a"
      node.href = url
   end
   return node
end


-- Construct a doctree node for an arc label, handling `url`, `id`, and `idurl`
--
local function getLabel(a)
   if a.label or a.id then
      local label = a.label or ""
      if a.id then
         label = {label, makeLink({type="sup", a.id}, a.idurl)}
      end
      return makeLink(label, a.url)
   end
end


-- Begin a rotated block.  Returns parameter to be passed to endRot().
--
local function beginRot(gc, gradient, skip, dy, src, dst, dx, path)
   local offset = math.max(gradient or 0, 0) + math.max((skip or 0)*dy, 0)
   if offset >= 1 and src ~= dst then
      local a,b = path[1], path[2]
      local rad = math.atan(offset / ((dst-src)*dx))
      local scale = round(1/math.cos(rad), 1000)

      local scaleStr = ""
      if math.abs((scale-1) * (b[1]-a[1])) >= 1.5 then
         scaleStr = " scale("..scale..",1)"
      end
      local pfmt = '-webkit-transform:rotate(%ddeg)%s;'..
                   '-webkit-transform-origin:%fpx %fpx;'
      local props = string.format(pfmt, round(math.deg(rad), 100),
                                  scaleStr, a[1], a[2])

      gc:emitHTML('<div style="position:relative;%s%s%s">',
                  props,
                  props:gsub("webkit", "moz"),
                  props:gsub("webkit", "ms"),
                  props:gsub("webkit", "o"))
      return gc
   end
end


local function endRot(gc)
   if gc then gc:emitHTML("</div>") end
end


-- Return the height of a box arc (including inter-box spacing)
--
local function getBoxHeight(a, dy, lineHeight)
   local nls = select(2, string.gsub(a.label or "", "\n", "%1"))
   return math.max(dy, (nls+2)*lineHeight)
end


-- Compute 'y' positions of each arc, accounting for arcskip and gradient
-- Determine whether `abox` is uses
--
local function scanArcs(m, options, y, dy, lineHeight)
   local arcY = {}
   local abox = false
   arcY[1] = y
   for n, arcgrp in ipairs(m.arcs) do
      local skip = 0
      local boxhgt = 0
      for _,a in ipairs(arcgrp) do
         if a.op == "abox" then
            abox = true
         end
         a.av = getValues(m, a.attrs, attrTypes)
         skip = math.max(skip, a.av.arcskip or 0)
         if a.op:match("box") then
            boxhgt = math.max(boxhgt, getBoxHeight(a.av, dy, lineHeight))
         end
      end
      local hgt = math.max(0, options.arcgradient or 0) + (skip+1)*dy
      y = y + math.max(hgt, boxhgt)
      arcY[n+1] = y
   end
   return arcY, abox
end


-- Render sequence chart, m, to gc
--
local function render(m, gc)
   if not m then
      return("<pre>msc: Syntax error</pre>")
   end

   local eattrs = {}  --  entity name/table --> entity attributes
   for ndx,e in ipairs(m.entities) do
      local a = getValues(m, e.attrs, attrTypes)
      a.ndx = ndx
      eattrs[e.key] = a
      eattrs[e] = a
   end

   local options = getValues(m, m.options, optionTypes)
   local w = options.width or 600
   if options.hscale then
      w = w * options.hscale
   end
   if options.float then
      gc.float = options.float
   end
   local hideEnts = (options.entities == "off")

   local lineHeight = 14
   local ne = #m.entities
   local boxw = 120   -- box width
   local boxh = 40   -- box width
   local dx = w / (ne>=1 and ne or 1)   -- width of entity
   local dy = 30                        -- height of arc
   local x0 = dx / 2 -- boxw/2
   local y0 = lineHeight * 1.5
   local spineWidth = 2

   if hideEnts then
      y0 = 0
   end

   local arcY, usesABOX = scanArcs(m, options, y0, dy, lineHeight)
   local maxy = arcY[#arcY]

   gc:setSize(w, maxy)
   gc.fontSize = 12
   gc.canvasClass = "msc"
   gc.lineHeight = lineHeight
   gc.arrowLength = 12
   gc.arrowWidth = 8

   -- draw entities

   gc.lineWidth = spineWidth
   for n, e in ipairs(m.entities) do
      local x = x0 + (n-1)*dx
      -- draw names
      if not hideEnts then
         local textColor = eattrs[e].textcolor
         local txt = eattrs[e].label or e.key
         gc:rect(x - dx/2, 0, dx, lineHeight, {
                    text = txt, textColor = textColor,
                 })
      end

      -- draw vertical lines
      local color = eattrs[e].linecolor or "#000"
      local yDrawn = y0
      local function vlineto(nArc, style)
         local y = arcY[nArc+1]
         if y > yDrawn then
            gc:path{ {x, yDrawn}, {x, y},
                     lineStyle=style, color = color }
            yDrawn = y
         end
      end
      for nArc, a in ipairs(m.arcs)  do
         if a[1] and a[1].op == "..." then
            vlineto(nArc-1)
            vlineto(nArc, "dotted")
         end
      end
      vlineto(#m.arcs)
   end


   ----------------------------------------------------------------
   -- draw arcs
   ----------------------------------------------------------------


   local function arcTextAttrs(label, arcAttrs, entAttrs, textAlign)
      return {
         text = label,
         textColor = arcAttrs.textcolor or entAttrs.arctextcolor,
         textBG = arcAttrs.textbgcolor or entAttrs.arctextbgcolor or "#fff",
         textAlign = textAlign
      }
   end

   -- Draw a single arc (with arrow or box)
   --
   local function drawArc(y, src, dst, op, label, arcAttrs, entAttrs)
      local xs, xd = x0+(src-1)*dx,  x0+(dst-1)*dx
      local xa, xb = minmax(xs, xd)

      if op:match("box") then
         -- draw box
         local ytop = y - dy*7/16
         local boxwid = dx * 7 / 8
         local boxhgt = getBoxHeight(arcAttrs, dy, gc.lineHeight) - dy*1/8
         xa = xa - boxwid/2
         xb = xb + boxwid/2
         local clr = arcAttrs.linecolor or nil
         if op:match("abox") then
            drawAngleBox(gc, xa, ytop + 0.5, xb-xa, boxhgt+1, label, clr)
         else
            local opts = {
               text = label, fill=true, fillColor="#fff", strokeStyle = "solid",
               radius = op:match("rbox") and gc.lineHeight/2, strokeColor = clr
            }
            if usesABOX then
               opts.lineWidth = 2
            else
               opts.shadow = true
            end
            gc:rect( xa, ytop, xb-xa, boxhgt, opts)
         end
         return
      end

      -- draw an arrow

      local astyle = arcStyles[op:gsub("<","")] or {}
      local color = arcAttrs.linecolor or entAttrs.arclinecolor
      local lw = astyle.lineWidth or gc.lineWidth
      local endcapwid = sign(xd-xs)*lw/2
      local path = { {xs + endcapwid,y}, {xd - endcapwid,y} }
      local top = y - gc.lineHeight - gc.lineWidth*2
      local align = nil

      if src == dst then
         -- loop back to self
         local wid = dx/3 * (src==1 and -1 or 1)
         local x2, y1, y2 = xs+wid, y-dy/4, y+dy/4
         path = { {xs,y1}, {x2,y1}, {x2,y2}, {xs,y2}, radius = dy/4 + lw/2 }
         -- label
         top = y1 - gc.lineHeight / 2
         if src==1 then
            xb = xb + dx
            align = "left"
         else
            xa = xa-dx
            align = "right"
         end
      end

      local rot = beginRot(gc, options.arcgradient, arcAttrs.arcskip, dy, src, dst, dx, path)

      if label then
         gc:rect( xa + spineWidth*2, top, xb-xa-spineWidth*4, gc.lineHeight,
                  arcTextAttrs(label, arcAttrs, entAttrs, align))
      end
      local b,a = path[#path-1], path[#path]  -- path ends at B -> A
      if op == "-x" then
         -- lost message
         a[1] = a[1]- (a[1]-b[1])/4   -- shorten last segment by 1/4
         gc:strokeX(a[1], a[2]+1, 4, color)
      elseif op:match(">") then
         -- arrow
         astyle.color = color
         gc:arrow(a, b, astyle)
         if op:match("<") then
            gc:arrow(path[1], path[2], astyle)              -- bi-directional
         end
      end

      path.lineStyle = astyle.lineStyle
      path.lineWidth = astyle.lineWidth
      path.color = color
      gc:path(path)

      endRot(rot)
   end

   -- Draw all arcs
   --
   -- Arcs delimited by "," exist in the same "group" (drawn at same Y index)

   gc.lineWidth = 1
   for n, arcgrp in ipairs(m.arcs) do
      local y = arcY[n] + dy/2
      for _,a in ipairs(arcgrp) do
         local attrs = getValues(m, a.attrs, attrTypes)
         local attrs = a.av
         local arcOp = a.op
         local label = getLabel(attrs)

         if a.lhs then
            -- arc with line
            local src, op, dst = a.lhs, a.op, a.rhs
            if r2l[op] then
               src, op, dst = dst, r2l[op], src
            end
            local from = eattrs[src]
            local to = eattrs[dst]
            if not from or (not to and dst ~= "*") then
               local e, pos = a.lhs, a.lpos
               if eattrs[e] then
                  e, pos = a.rhs, a.rpos
               end
               m.warn(pos, "msc: unknown entity: %s", e)
            elseif to then
               -- single line
               drawArc(y, from.ndx, to.ndx, op, label, attrs, from)
            else
               -- broadcast
               for ndx = 1, ne do
                  if ndx ~= from.ndx then
                     drawArc(y, from.ndx, ndx, op, nil, attrs, from)
                  end
               end
               if label then
                  local top = y - gc.lineHeight - gc.lineWidth*2
                  gc:rect(0, top, dx * ne, gc.lineHeight,
                          arcTextAttrs(label, attrs, from))
               end
            end
         else
            -- "pseudo" arc

            if arcOp == "---" then
               gc:path{ {0,y}, {w,y}, lineStyle="dashed", color=attrs.linecolor}
            end
            if label then
               gc:rect(0, y-gc.lineHeight/2, w, gc.lineHeight,
                       arcTextAttrs(label, attrs, {}))
            end
         end
      end
   end
end

return {
   render = render,
   parse = parse,
}
