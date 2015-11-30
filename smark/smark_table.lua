-- ".table" macro
--
-- Construct table from boxes delimited by ASCII lines
--

local memoize = require "memoize"
local smarklib = require "smarklib"

local E, TYPE = smarklib.E, smarklib.TYPE
local insert = table.insert


local function lineCmp(a,b)
   return a[1] < b[1]
end


-- Detect horizontal lines in text.  Return array of { y, x1, x2, str }.  x1
-- & x2 identify the first and last cells occupied by the line (1-based).  y
-- is the line (1-based).  str is the string of characters that constitute
-- the line.
--
local function getHLines(xyt)
   local hlines = {}
   for pos, str in xyt.text:gmatch("()(%+[%+%-=]+%+)") do
      local x, y = xyt:getXY(pos)
      insert(hlines, { y, x, x+#str-1, str} )
   end
   return hlines
end


-- Detect vertical lines. Return array of { x, y1, y2 }
--
local function getVLines(xyt)
   local vlines = {}

   --   columns[ncol][row] = length of vline ending at row
   local columns = memoize.newTable(function () return {} end)
   for pos in xyt.text:gmatch("()[%+|]") do
      local x, y = xyt:getXY(pos)
      local col = columns[x]
      if col[y-1] then
         col[y] = col[y-1] + 1
         col[y-1] = nil
      else
         col[y] = 1
      end
   end

   for x, col in pairs(columns) do
      for y, len in pairs(col) do
         if len > 2 then
            insert(vlines, {x, y-(len-1), y})
         end
      end
   end

   table.sort(vlines, lineCmp)
   return vlines
end


-- XYText class
--
local function newXYText(source)
   local text = source.data
   local self = { text=text, 1 }

   for pos in text:gmatch("\n()") do
      insert(self, pos)
   end

   -- GetXY() : translate byte offset into x,y
   --
   local y = 1
   function self:getXY(pos)
      while pos < self[y] and y > 1 do
         y = y - 1
      end
      while pos >= (self[y+1] or math.huge) do
         y = y + 1
      end
      return pos - self[y] + 1, y
   end

   -- Construct sub-rectangle of text, returning a source object
   --
   function self:sourceRect(x1,y1,x2,y2)
      local runs = {}
      for y = y1, y2 do
         local pos = self[y]
         local posmax = (self[y+1] or #pos+2) - 2
         local a = math.min(pos + x1 - 1, posmax+1)
         local b = math.min(pos + x2 - 1, posmax)
         insert(runs, {a,b})
      end
      return source:extract(self[y1]+x1-1, runs, "\n")
   end

   return self
end


-- Find all cell boundaries for this row spanning y1...y2.
--
local function scanRow(vl, y1, y2, f)
   local left, leftcol = (vl[1] and vl[1][1]), 1
   local col, colx = 0, 0
   for _, v in ipairs(vl) do
      local x, ya, yb, str = table.unpack(v)
      if x > colx then
         col = col + 1
         colx = x
      end
      if ya<=y1 and yb>=y2 then
         if x > left then
            local colspan = col - leftcol
            f(left, x, colspan, (str or ""):sub(y1-ya+1, y2-ya+1))
            left = x
            leftcol = col
         end
      end
   end
end


local nonSpecialAttrs = { [1] = true, [TYPE]=true, _source=true }

local function canUnwrap(node)
   if type(node) ~= "table" or (node[TYPE] or "div") ~= "div" then
      return false
   end
   for k in pairs(node) do
      if not nonSpecialAttrs[k] then
         return false
      end
   end
   return true
end


local function parse(src)
   local doc = smarklib.parse(src)
   while canUnwrap(doc) do
      doc = doc[1]
   end
   return doc
end


-- Find all lines connected to the left-most vertical line.
--
local function getOutermostLines(hin, vin)
   local hout, vout = {}, { table.remove(vin, 1) }

   -- *.u = unconnected lines,  *.c = connected,  *.n = number visited in v.c
   local v = { u = vin, c = vout, n=0 }
   local h = { u = hin, c = hout, n=0 }

   while true do
      local nconn = #h.c
      while v.n < #v.c do
         v.n = v.n + 1
         local x, y1, y2 = table.unpack(v.c[v.n])

         -- move lines that touch this one from h.u to h.c
         local nn = 1
         for n = 1, #h.u do
            local l = h.u[n]
            h.u[n] = nil

            local y, x1, x2 = table.unpack(l)
            if y1<=y and y<=y2 and x1<=x and x<=x2 then
               insert(h.c, l)
            else
               h.u[nn] = l
               nn = nn + 1
            end
         end
      end
      if nconn == #h.c then break end
      h, v = v, h
   end

   table.sort(hout, lineCmp)
   table.sort(vout, lineCmp)

   return hout, vout
end


-- Construct a table from plain text
--
local function makeTable(source)
   local xyt = newXYText(source)

   -- detect all lines
   local hl = getHLines(xyt)
   local vl = getVLines(xyt)

   -- keep only the outermost lins
   hl, vl = getOutermostLines(hl, vl)

   -- count columns & mark positions
   local cols = {}
   for _, v in ipairs(vl) do
      local x = v[1]
      if cols[#cols] ~= x then insert(cols, v) end
   end

   -- output rows
   local tbl = E.table{}
   local top = hl[1] and hl[1][1]
   local spans = {}    -- spans[ncol] = next row to display (after rowspan)
   local nrow = 0
   for _, h in ipairs(hl) do
      local y = h[1]

      if y > top then
         nrow = nrow + 1
         -- output row from `top` to `y` inclusive
         local row = E.tr{}
         local ncol = 1

         -- visit each cell in row

         local function rowcell(x1,x2,colspan)
            if (spans[ncol] or 0) > nrow then ncol = ncol + colspan ; return end

            -- look for bottom of cell to determine rowspan & header-ness
            local ymax = y
            local rowspan = 1
            local chars
            scanRow(hl, x1, x2, function (y1, y2, r, ch)
                                  if y1 == top then
                                     rowspan = r
                                     chars = ch
                                     ymax = y2
                                  end
                               end)

            local src = xyt:sourceRect(x1+1,top+1,x2-1,ymax-1)
            local tree = parse(src)

            local typ = chars:match("=") and "th" or "td"
            local cell = E(typ) {
               tree,
               colspan = colspan>1 and colspan or nil,
               rowspan = rowspan>1 and rowspan or nil,
            }
            insert(row, cell)

            -- mark rowspans
            for nn = 1, colspan do
               spans[ncol] = nrow + rowspan
               ncol = ncol + 1
            end
         end

         scanRow(vl, top, y, rowcell)
         insert(tbl, row)
         top = y
      end
   end

   return tbl
end


local function expand(node, doc)
   return makeTable(node._source)
end

return expand
