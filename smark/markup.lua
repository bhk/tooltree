----------------------------------------------------------------
-- markup: read Smark files, constructing DocTree format
----------------------------------------------------------------

local smarkmisc = require "smarkmisc"
local lpeg = require "lpeg"
local htmlrefs = require "htmlrefs"
local utf8utils = require "utf8utils"
local Object = require "object"
local Source = require "source"
local Html2D = require "html2d"
local doctree = require "doctree"

local insert = table.insert
local E, TYPE = doctree.E, doctree.TYPE
local urlEncode = smarkmisc.urlEncode


local function iclone(tbl)
   local o = {}
   for ndx, v in ipairs(tbl) do
      o[ndx] = v
   end
   return o
end

----------------------------------------------------------------
-- List tag syntax
--
--    -  Unordered list item
--    *  Unordered
--    #. Ordered  (one or two '#' characters before '.')
--    1. Ordered  (one or two digits before '.')
--    1. Ordered  (one or two digits before ')')
--    A) Ordered  (one or two alpha characters before ')'
--    a) Ordered
----------------------------------------------------------------

-- linePEG:  text -->  posTag, tag, posLine, line, posNextLine
local linePEG do
   local P, S, R, C, Cp = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.Cp

   -- r12: match one or two of R(...)
   local function r12(...)
      return R(...) * (R(...) + P"")
   end

   local function oneOrTwo(c) return c*c^1 end

   local pNL  = P"\n" + "\n"
   local pTag = ( C(S"*-")
                + r12("AZ") / "A" * ")"
                + r12("az") / "a" * ")"
                + r12("09","##") / "1" * S".)"
                ) * P" "^1

   linePEG = P" "^0 * Cp() * (pTag + C"") * Cp() * C((1-pNL)^0) * Cp() * pNL^-1
end


----------------------------------------------------------------
-- Layout: Indentation and Paragraphs
--
-- Layout is described as a tree of nodes. There are two types of nodes:
--
--   1. A text line, which is a two-element array, {<number>, <number>},
--      giving the start and end position in the document of the text.  Text
--      lines include the end of line character.
--
--   2. A block is a table of child nodes (1...N) and the following fields:
--        i    = indentation level (starting column, 0-based)
--        tag  = list tag
--        tagi = indentation level of tag (not usually significant, but
--               needed to recover origina text for macros)
--
-- All layout nodes have these fields/methods:
--
--    source    : the original source object
--    IsBlank() : true if the node is blank line
--    IsBlock() : true if the node is a block node (versus a text line)
--
-- List tags -- "1.", "#.", "a)", "*", or "-" -- signify lists.  List tags
-- have nodes of their own, independent from (and containing) the paragraph
-- they mark.  A list tag node's indentation is its paragraph's indentation
-- minus 0.5.
--
----------------------------------------------------------------


local LayoutNode = Object:new()

function LayoutNode:__tostring()
   if self.i then return nil end
   return self.source.data:sub(self[1], self[2])
end

function LayoutNode:isBlank()
   return self[1] and self[1]==self[2]
end

function LayoutNode:isBlock()
   return self.i ~= nil
end

function LayoutNode:new(t)
   return self:adopt(t or {})
end

-- Note: this matches against the original string, so it MIGHT scan past the
-- end, and any position captures are relative to self.source.
function LayoutNode:match(pattern, init)
   return self.source.data:match(pattern, (init and self[1]+init-1 or self[1]))
end


-- parseLayout: Return tree of layout nodes.
--
local function parseLayout(source)
   -- instantiate a node class for this string
   local str = source.data
   local Node = LayoutNode:new {source=source}
   local parent = {}
   local top = Node:new{i=0}
   local node = top
   local ndx = 1

   -- enter/leave level of nesting
   local function nest(p, tag, tagi)
      local i = p - ndx
      while i < node.i do
         node = parent[node]
      end
      if node.i == i and node.tag ~= tag then
         node = parent[node]
      end
      if i > node.i then
         local t = Node:new{ i = i, tag = tag, tagi = tagi and tagi-ndx }
         parent[t] = node
         insert(node, t)
         node = t
      end
   end

   while ndx <= #str do
      local p0, tag, p1, txt, p2 = linePEG:match(str, ndx)
      if txt ~= "" then
         if tag ~= "" then
            nest(p1-0.5, tag, p0)
         end
         nest(p1)
      elseif tag ~= "" then
         Node.source:warn(p0, 'ignoring list tag "%s" with empty paragraph',
                           str:match("[^ ]*", p0))
      end

      insert(node, Node:new{p1, p2})
      ndx = p2+1
   end

   return top
end

----------------------------------------------------------------
-- Inline markup
--   *i*  **b**   `code`  [[Section]]  [text](url)
----------------------------------------------------------------

-- local links are expanded in a second pass through the document
local function makeLocalLink(node, doc)
   local u = urlEncode(node.link)
   if not doc.anchors[u] then
      doc:warn(node, 0, "Missing target for link '%s'", node.link)
   end

   local elem = iclone(node)
   elem[TYPE] = "a"
   elem.href = "#"..u
   return elem
end

local function expandLocalLink(node)
   node.expand = makeLocalLink
   return E._defer { node }
end



local parseInline do
   local P, S, C, R, V = lpeg.P, lpeg.S, lpeg.C, lpeg.R, lpeg.V
   local Cb, Cc, Cp, Cs, Ct, Cg, Cmt = lpeg.Cb, lpeg.Cc, lpeg.Cp, lpeg.Cs,
      lpeg.Ct, lpeg.Cg, lpeg.Cmt

   -- variables: these are modified on each parse operation
   local currentSource
   local inquote = false

   local spcChar = S" \n"
   local spc = spcChar^0
   local lit = spcChar^1/" " + 1   -- literal character (no markup)
   local alnum = R("AZ", "az", "09")

   -- Match only valid UTF-8 characters
   local utf8Char = ( R"\0\127" +
                      R"\194\223" * R"\128\191" +
                      P"\224"     * R"\160\191" * R"\128\191" +
                      R"\225\239" * R"\128\191" * R"\128\191" +
                      P"\240"     * R"\144\191" * R"\128\191" * R"\128\191" +
                      R"\240\243" * R"\128\191" * R"\128\191" * R"\128\191" +
                      P"\244"     * R"\128\143" * R"\128\191" * R"\128\191" )

   local uchar = utf8utils.encode

   local function mtNonUTF(s, i, match)
      currentSource:warn(i-#match, "invalid UTF-8 character; assuming ISO-Latin-1" )
      return true, uchar(match:byte())
   end
   local litChar = C(utf8Char) + Cmt(C(1), mtNonUTF)

   -- mtWarn() : match a token but emit a warning about it.
   local function mtWarn(s,i,match)
      currentSource:warn(i - #match,
                         "unbalanced/unescaped markup symbol: %s",
                         match:gsub("[ \n]$","") )
      return true, match
   end

   -- Concatenate consecutive strings in an array of captures.
   -- Modifies t and returns it.
   local function catStrings(t)
      local o = 1
      for i = 2, #t do
         local s = t[i]
         t[i] = nil
         if type(s) == "string" and type(t[o]) == "string" then
            t[o] = t[o] .. s
         else
            o = o + 1
            t[o] = s
         end
      end
      return t
   end


   -- Create a doctree node
   --
   local function mkNode(t,typ)
      catStrings(t)
      t[TYPE] = typ
      return t
   end

   --  Match ```....```   (one or more '`')

   -- match-time function that matches its first capture
   local function atCap(s,i,cap)
      return s:sub(i,i+#cap-1) == cap and i+#cap
   end
   local codeEnd = Cmt(Cb"code", atCap)
   local code = ( Cg(P'`'^1,"code") * spcChar^-1
                  * Ct( Cs((lit - spcChar^-1*codeEnd)^1) ) * spcChar^-1
                  * codeEnd * Cc"code" / mkNode )
                + Cmt(P"`", mtWarn)

   -- match & replace named or numeric reference
   --
   local function mkRef(i,s)
      local n = htmlrefs[s] or
                 tonumber(s:match("^#(%d+)$") or "") or
                 tonumber( s:match("^#[xX](%x+)$") or "", 16)
      if not n then
         currentSource:warn(i-1, "unrecognized entity reference: &%s;", s)
         return "&"..s..";"
      end
      return uchar(n)
   end

   local function atDQ()
      inquote = not inquote
      return uchar(inquote and 0x201C or 0x201D)
   end

   -- explicit line break (capture = E.br{})

   local function atBR(s,i,n)
      return true, E.br{}
   end
   local linebreak = "\\" * P" "^0 * Cmt("\n" + P(-1), atBR) * spc


   -- macros

   local function atMacro(s, i, name, pos)
      local subsrc = currentSource:extract(pos - 1 - #name, {{pos,i-2}})
      return true, E._macro{macro=name, _source=subsrc, text=subsrc.data}
   end
   local mname = alnum^1
   local mtext = P {
      (lit - S"{}"  + V"matched")^0,
      matched = P"{" * V(1) * P"}"
   }
   local macro = P"\\" * Cmt( C(mname) * "{" * Cp() * mtext * "}", atMacro)


   -- chars:  The bottom layer of markup (no non-terminals).  Will not consume
   --         un-escaped "*", "[", "]".

   local chars = Cs( alnum^1
                      + S".,:()"
                      + spcChar^1 / " " * (P"*"^1 * #spcChar + "")
                      + "&" * Cp() * C(P"#"^-1 * (alnum)^1) * ";" / mkRef
                      + P'<--' / uchar(0x2190)
                      + P'-->' / uchar(0x2192)
                      + P'<==' / uchar(0x21D0)
                      + P'==>' / uchar(0x21D2)
                      + P'<=>' / uchar(0x21D4)
                      + P'!=' / uchar(0x2260)
                      + P'<=' / uchar(0x2264)
                      + P'>=' / uchar(0x2265)
                      + P'--'  / uchar(0x2014)
                      + P"\\"/"" * S[[!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~]]
                      )^1
               + P'"'   / atDQ
               + linebreak
               + macro
               + (litChar - S"*][")

   -- match an ending token but only if NOT following a space
   local function ET(tok)
      return function(s,i)
         if not s:sub(i-1,i-1):match("[ \n]") and s:sub(i,i+#tok-1) == tok then
            return i+#tok, (#tok == 1 and "i" or "b")
         end
      end
   end

   local function isempty(s,i,c)
      if c == "" then return i end
   end

   local function notIn(name)
      return Cmt(Cb(name),isempty)
   end

   -- enter a construct, but only if not already nested in it
   local function enter(name)
      return P(name) * notIn(name) * Cg(Cp(),name)
   end

   local function rtrimNode(node)
      if type(node[#node]) == "string" then
         node[#node] = smarkmisc.rtrim(node[#node])
      end
   end

   local g = {
      -- initialize these groups with empty strings (otherwise
      -- Cb() will generate an error) and then parse markup
      Cg("","*") * Cg("", "**") * Cg("", "[") * V"m"
   }

   -- m = top-level markup & text

   g.m = Ct( ( V"b"
               + V"i"
               + V"link"
               + V"href"
               + V"url"
               + code
               + chars
               + notIn"[" * C(S"][")
               + notIn"*" * notIn"**" * Cmt(C("*"*P"*"^-1),mtWarn)
           )^1 ) / catStrings

   -- b = **bold**

   g.b = enter"**" * #-spcChar * V"m" * ET"**" / mkNode

   -- *italic*

   g.i = (enter"*" - "**") * #-spcChar * V"m" * ET"*" / mkNode

   -- [[text]]
   -- [[@name]]

   local function linkNode(at, pos, node)
      rtrimNode(node)
      if at == "@" then
         node[TYPE] = "a"
         node.name = doctree.treeConcat(node)
      else
         node[TYPE] = "_object"
         node.expand = expandLocalLink
         node.link = doctree.treeConcat(node)
      end
      node._source = currentSource:newWarner(pos)
      return node
   end

   g.link = enter"[" * "[" * Cs(P"@"^-1) * spc * Cp() * V"m" * "]]" / linkNode

   -- [text](href)
   -- [text](@name)

   local function hrefNode(node, at, pos, href, title)
      rtrimNode(node)
      node[TYPE] = "a"
      if at == "@" then
         node.name = href
      else
         node.href = smarkmisc.urlNormalize(href)
      end
      node.title = title
      node._source = currentSource:newWarner(pos)
      return node
   end

   g.href = enter"[" * spc * V"m" * "]" * spc
            * "(" * Cs(P"@"^-1) * spc * Cp() * Cs( (lit - spcChar^0*S'")')^0 ) * spc
            * ( '"' * Cs( (lit - spc*P'"')^0 ) * spc * '"' * spc + "" )
            * ")" / hrefNode

   local scheme = P"http:" + "https:" + "ftp:" + "mailto:"

   -- <http:...>

   local function urlNode(url)
      return E.a {
         url,
         href = smarkmisc.urlNormalize(url),
      }
   end
   g.url = "<" *  #scheme * Cs( (spcChar^1/" " + (1-P">"))^1 ) * ">" / urlNode

   local mu = P(g)

   ------------------------------------------------------------------------

   -- Parse inline markup.  Returns an array of strings/nodes.
   --
   function parseInline(source)
      currentSource = source
      inquote = false
      return mu:match( smarkmisc.rtrim(source.data) )
   end
end


----------------------------------------------------------------
-- Group lines into paragraphs, lists, preformatted blocks
----------------------------------------------------------------


-- Add all lines from a layout subtree to runs[]
--
-- i = base indentation level
--
local function getLines(node, a, b, runs, i)
   i = math.floor(i or node.i)
   for x = a, b do
      local child = node[x]
      if child:isBlock() then
         getLines(child, 1, #child, runs, i)
      else
         local r = child
         if r[1] < r[2] then
            -- un-indent
            r = {child[1] - (node.i - i),  child[2]}
         end
         insert(runs, r)
      end
   end
end


local function makeParg(typ, node, a, b)
   local runs = {}
   getLines(node, a, b, runs)
   local t = parseInline( node.source:extract(nil, runs) )
   t[TYPE] = typ
   return t
end


local hdrTags = {
   ["#"] = "h1",
   ["="] = "h2",
   ["-"] = "h3",
   ["."] = "h4"
}


-- Process a consecutive sequence of lines
--
--   parg[a...b] = layout node lines that constitute the paragraph
--
local function formatParg(parg, a, b)
   -- Headers underlined with "===" or "---"
   if b - a >= 1 then
      local u, pos = parg[b]:match("^([#=.-])[#=.-]* *()")
      if pos == parg[b][2] then
         return makeParg(hdrTags[u], parg, a, b-1)
      end
   end

   -- HR
   if b == a and parg[a]:match("^[-=][-=][-=]+ *()") == parg[a][2] then
      return E.hr{}
   end

   -- see if all lines are prefixed with ":" or "." and find first non-space
   local indent, prefix = 99999999, ""
   for n = a,b do
      local line = parg[n]
      local posln, pre
      pre, posln = line:match("^([:%.;%+|]) *()")
      if not pre then prefix = "" ; break end
      if not prefix:find(pre, 1, true) then
         prefix = prefix .. pre
      end
      if posln < line[2] then
         -- indent == bytes *preceding* first non-space byte
         indent = math.min(indent, posln - line[1])
      end
   end

   if prefix == ";" then
      return nil
   end

   local isTable = prefix=="+|"

   -- Preformatted text, .art, or .table
   if isTable or ((prefix=="." or prefix==":") and indent >= 2) then
      local chop = isTable and 0 or indent
      local maxlen = 0
      local runs = {}

      getLines(parg, a, b, runs)
      for _, r in ipairs(runs) do
         r[1] = math.min(r[2], r[1]+chop)    -- get at least the '\n'
         maxlen = math.max(maxlen, r[2]-r[1]+1)
      end

      local src = parg.source:extract(nil, runs)
      local data = src.data
      local t
      if isTable then
         t = E._macro{macro="table", text=data, _source=src }
      elseif prefix==":" then
         t = E._macro{macro="art", text=data, _source=src }
      else
         t = E.pre{ data }
         if maxlen > 80 then
            t.style = string.format("font-size: %d%%", (8000 * 0.90 / maxlen))
         end
      end
      return t
   end

   -- regular paragraphs
   return makeParg("p", parg, a, b)
end


-- map 'style' to element name & attributes
local listStyles = {
   ["1"] = { [TYPE]="ol", type="1" },
   ["a"] = { [TYPE]="ol", type="a" },
   ["A"] = { [TYPE]="ol", type="A" },
   ["*"] = { [TYPE]="ul" },
   ["-"] = { [TYPE]="ul", type="circle" },
}


-- markupDoc: group lines into paragraphs and apply block-level and inline
-- markup
--
local function markupDoc(node, parent)
   local source = assert(node.source)

   local t = {_source = source}
   local ls = listStyles[node.tag]
   if ls then
      t[TYPE] = ls[TYPE]
      t.type = ls.type
   elseif parent and parent.tag then
      t[TYPE] = "li"
   end

   local ndx = 1
   while node[ndx] do
      local e = node[ndx]

      if e:isBlock() then
         -- block node

         local m = markupDoc(e, node)
         if e.i - node.i >= 4 then
            m[TYPE] = m[TYPE] or "div"
            m.class = "indent"
         end
         insert(t, m)
         ndx = ndx + 1
      else
         -- text node

         -- consume non-blank lines
         local ndxStart = ndx
         while node[ndx] and not node[ndx].i and not node[ndx]:isBlank() do
            ndx = ndx + 1
         end

         if ndx > ndxStart then
            -- paragraph
            local line = node[ndxStart]
            local macro, d, argp = line:match("^%.([%a_][%w_%-%.]*) *(:?) *()")

            if macro == "end" then
               source:warn(line[1], "Mismatched macro end.")
            end
            if ndx == ndxStart+1 and macro and (d==":" or argp==line[2]) then
               -- find args: single-line, or muti-line

               local runs = {}
               if d == ":" then
                  -- single-line
                  insert(runs, {argp, line[2]})
               else
                  -- multi-line: consume up to first non-indented line
                  local imin = math.huge
                  while node[ndx] and (node[ndx].i or node[ndx]:isBlank()) do
                     local i = node[ndx].tagi or node[ndx].i
                     if i then
                        imin = math.min(imin, i)
                     end
                     ndx = ndx + 1
                  end
                  getLines(node, ndxStart+1, ndx-1, runs, imin)

                  while runs[1] and runs[#runs][1] == runs[#runs][2] do
                     table.remove(runs)
                  end

                  -- consume matching macro termination
                  local endmacro = node[ndx] and node[ndx]:match("^%.end +([^ \n]*)")
                  if endmacro == macro then
                     ndx = ndx + 1
                  end
               end

               local ss = source:extract(line[1]+1, runs)
               insert(t, E._macro{macro=macro, text=ss.data, _source=ss})

            elseif ndx==ndxStart+1 and line[1]==line[2]-1 and line:match("^%.") then
               -- single ".": ignore
            else
               -- paragraph
               insert(t, formatParg(node, ndxStart, ndx-1) )
            end
         end
         while node[ndx] and node[ndx]:isBlank() do
            ndx = ndx + 1
         end
      end
   end
   return t
end


-- Generate DocTree from plain text.  The returned DocTree represents a
-- fragment of HTML content, perhaps with interspersed HEAD elements.  The
-- top of the tree is a DIV element.
--
-- Overview of parsing:
--
--    parseDoc : plain text -> doc tree
--      parseLayout : plain text -> layout tree  (lines/indentation/lists)
--      markupDoc : layout tree -> doc tree      (pargs, block & inline markup)
--        markup : string -> doc tree            (inline markup)
--
--
local function parseDoc(source)
   -- Backwards compatibility hacks: callers should be providing a source
   -- object to get accurate error location reporting
   if type(source) == "function" then
      io.stderr:write("Warning: source function (not object) supplied to parseDoc()")
      assert(not os.getenv("SMARK_WERR"))
      source = source()
   end
   if type(source) == "string" then
      io.stderr:write("Warning: source string (not object) supplied to parseDoc()")
      assert(not os.getenv("SMARK_WERR"))
      source = Source:newString(nil, source)
   end

   return markupDoc( parseLayout(source) )
end


----------------------------------------------------------------

-- `macros` holds loaded macro classes, index by macro name
--
local macros = {}


-- Return a macro class, loading it if necessary.  If an error is
-- encountered, a null macro (returning its contents) is installed.
--
local function loadMacro(doc, node, name)
   local mmod = macros[name]
   if not mmod then
      local succ, r = pcall(require, "smark_"..name)
      if not succ then
         doc:warn(node, 0, "%s", r)
      end
      mmod = r
   end
   if type(mmod) == "function" then
      mmod = { expand = mmod }
   elseif type(mmod) ~= "table" then
      doc:warn(node, 0, "macro library %s did not return function or table", name)
      mmod = { expand = function (x) return x.text end }
   end
   return mmod
end


----------------------------------------------------------------
-- built-in macros
----------------------------------------------------------------

--------------------------------
-- css
--------------------------------

function macros.css(node)
   return E.head { E.style { type="text/css", node.text } }
end


--------------------------------
-- comment
--------------------------------

function macros.comment() end


--------------------------------
-- toc: Table of Contents
--------------------------------


-- Create TOC from all headers that follow tocNode
--
-- Any extraneous outermost nesting is stripped -- i.e., remove the level
-- reserved for H1 if there are no H1 elements.
--
-- The entire TOC is enclosed in a DIV with class="toc".  For each header
-- listed in the TOC there is a DIV with class="tocLevel".  A header's
-- tocLevel contains the link to the header followed by the tocLevels for
-- subordinate headers.
--
local function genTOC(tocNode, doc)
   local tree = doc.top

   -- toc[] holds a tree of tocLevel DIVs
   local toc = E.div {}

   -- latest[] returns the most recent toc/tocLevel node at a given level
   local latest = { [0] = toc }

   -- visit all nodes, populating toc tree

   -- iteration state
   local afterTOC, prevLevel = false, 0

   local function visit(node)
      if not afterTOC then
         afterTOC = node == tocNode
         return
      end
      local lvl = node._toclvl
      if lvl and lvl > 0 then
         -- create a tocLevel for this header, plus any intermediate ones if
         -- this header is deeper than 1 + the previous header's level.
         for level = math.min(lvl, prevLevel+1), lvl do
            local new = E.div { class="tocLevel" }
            insert(latest[level-1], new)
            latest[level] = new
         end
         insert(latest[lvl], E.a { href="#"..node._tocname, node._toctext })
         prevLevel = lvl
      end
   end

   doctree.visitElems(tree, visit)

   -- Remove empty levels at top
   while not toc[2] and toc[1] and toc[1][1].class == "tocLevel" do
      toc = toc[1]
   end

   toc.class = "toc"
   return toc
end


function macros.toc(node, doc)
   node.expand = genTOC
   return E._defer { node }
end

----------------------------------------------------------------
-- assign header anchor names & create anchor nodes
----------------------------------------------------------------

-- Find a unique anchor name for a header node.  On conflict, the node lower
-- in the hierarchy shall have a prefix appended.  Nodes explicitly assigned
-- names are not modified.
--
local function nameNode(node, name, anchors)
   local prev = anchors[name]
   if prev and (not prev._toclvl or prev._toclvl <= node._toclvl) then
      nameNode(node, "_"..name, anchors)
   else
      node._tocname = name
      anchors[name] = node
      if prev then nameNode(prev, "_"..name, anchors) end
   end
end


-- Assign anchor names to and "_toc..." fields to header elements, and set
-- doc.title to first H1
--
local function markAnchors(doc)
   local a = doc.anchors or {}
   doc.anchors = a

   -- scan for all explicitly assigned anchor names
   local function scanAnchors(node)
      if node.name and not a[node.name] then
         a[node.name] = node
      end
   end
   doctree.visitElems(doc.top, scanAnchors, 'a')

   -- auto-generate names for headers
   local function nameHeaders(node)
      local lvl = tonumber(node[TYPE] and node[TYPE]:match("^h(%d)$") or 0)
      if lvl > 0 and not node._toclvl then
         node._toclvl = lvl
         node._toctext = doctree.treeConcat(node)
         nameNode(node, urlEncode(node._toctext), a)
         insert(node, 1, E.a{ name = node._tocname })
         if lvl == 1 and not doc.title then
            doc.title = node._toctext
         end
      end
   end
   doctree.visitElems(doc.top, nameHeaders)
end


-- Activate and expand macros
--
-- See smarkmisc.lua for DocTree structure.  This module understands the
-- following special node types:
--
--    When node[TYPE] == "_macro":
--      node.macro  = macro name
--      node.text   = text content (parameters)
--      node._source = event function for args
--
--    When node[TYPE] == "_object":
--      node.expand, node.render2D = functions to render the object
--
local function expand(node, doc)
   if type(node) ~= "table" then
      return node
   end

   -- defer to next cycle?

   if node[TYPE] == "_defer" then
      node[TYPE] = nil
      insert(doc.expandNodes, node)
      return node
   end

   -- convert _macro to _object

   if node[TYPE] == "_macro" then
      -- macro as parsed from source:  convert to object
      local mmod = loadMacro(doc, node, node.macro)
      node[TYPE] = "_object"
      setmetatable(node, { __index = mmod })
   end

   -- expand object

   if node[TYPE] == "_object" then
      local exp = node.text  -- result of expansion

      if node.render2D then
         local gc = Html2D:new()
         local succ, r = pcall(node.render2D, node, gc)
         if succ then
            exp = gc:genTree()
         else
            doc:warn(node, 0, "error invoking object.render2D:\n%s\n", tostring(r))
         end
      elseif node.expand then
         local succ, r = pcall(node.expand, node, doc)
         if succ then
            exp = r
         else
            doc:warn(node, 0, "error invoking object.expand\n" .. tostring(r))
         end
      else
         doc:warn(node, 0, "cannot render this object: %s\n", tostring(node.macro))
      end

      node = expand(exp, doc)

   elseif type(node) == "table" and tostring(node[TYPE]):sub(1,1) ~= "_" then

      -- recursively expand children

      local ndxOut = 1
      for ndx = 1, #node do
         -- expand may return nil
         local child = expand(node[ndx], doc)
         node[ndx] = nil
         if child then
            node[ndxOut] = child
            ndxOut = ndxOut + 1
         end
      end
   end

   return node
end


local function Doc_warn(self, node, pos, ...)
   local source = (node and node._source) or self.top._source or Source
   source:warn(pos, ...)
end


-- expandDoc() modifies nodes in the document tree, replacing _macro and
-- _object nodes.
--
local function expandDoc(tree, configEnv)
   assert(type(tree) == "table" and tostring(tree[TYPE]):sub(1,1) ~= "_")

   -- 'doc' holds expansion state.  It is also made available to macros.
   local doc = {
      parse = parseDoc,
      macros = macros,
      config = configEnv or {},
      warn = Doc_warn,
      expandNodes = {tree},
      top = tree,
   }

   local n = 1
   while n <= #doc.expandNodes do
      expand(doc.expandNodes[n], doc)
      markAnchors(doc)
      n = n + 1
   end

   if doc.title then
      -- put this last in the document, so any other title element will
      -- override it when Normalize() is called.
      insert(tree, E.head { E.title { doc.title }} )
   end

   local a = {}
   local function checkAnchors(node)
      if node.name then
         local othernode = a[node.name]
         if othernode then
            doc:warn(node, 0, "duplicated anchor name '%s'", node.name)
            if othernode._source then
               othernode._source:warn(0, "... anchor also used here:")
            end
         end
         a[node.name] = node
      end
   end
   doctree.visitElems(tree, checkAnchors, 'a')

   tree[TYPE] = "div"
   tree.class = "smarkdoc"
   return tree
end


return {
   parseDoc = parseDoc,
   expandDoc = expandDoc
}
