-- Quick and dirty XML parser.
--

local utf8utils = require "utf8utils"

local insert, remove, concat = table.insert, table.remove, table.concat

local xml = {}

----------------------------------------------------------------
-- Decode entities
----------------------------------------------------------------

local utf8Encode = utf8utils.encode

local entities = {
   amp = "&",
   quot = '"',
   apos = "'",
   lt = "<",
   gt = ">",
}

local function decodeEntity(str)
   local res = entities[str]
   if res then
      return res
   end
   local n
   if str:sub(1,2) == "#x" then
      n = tonumber(str:sub(3), 16)
   elseif str:sub(1,1) == "#" then
      n = tonumber(str:sub(2))
   end
   if n then
      return utf8Encode(n)
   end
   return str
end

local function decodeText(txt)
   return (txt:gsub("&(#?%w+);", decodeEntity))
end

xml._decodeText = decodeText  -- for testing


------------------------------------------------
-- SAX parser
------------------------------------------------


-- maxBuffer limits the size of individual attribute names, values, PCDATA
-- and CDATA sections.
--
xml.maxBuffer = 1e7


-- Partial XML syntax reference:
--
-- content      = CharData? ((element | Reference | CDSect | PI | Comment) CharData?)*
-- element      = EmptyElemTag | STag content ETag
-- EmptyElemTag = '<' Name (S Attribute)* S? '/>'
-- STag         = '<' Name (S Attribute)* S? '>'
-- ETag         = '</' Name S? '>'
-- CDSect       = '<![CDATA[' Char* ']]>'
-- PI           = '<?' Name (S (Char* - (Char* '?>' Char*)))? '?>'
-- Comment      = '<!--' ((Char - '-') | ('-' (Char - '-')))* '-->'
-- Attribute    = Name Eq AttValue
-- Name         = NameStartChar NameChar*
-- Eq           = S? '=' S?
-- CharData     = [^<&]* - ([^<&]* ']]>' [^<&]*)


-- `tagPat` matches the start of ETag, STag, CDSect, PI, or Comment, which
-- are the things that can terminate PCDATA.  tagPat ensures that some ">"
-- is matched to guarantee it gets the complete the tag name for ETag and
-- STag, and the closing ">" or "/>" when there are no attributes.  (This
-- ">" is not necessarily the one that terminates the ETag/CDSect/etc.)

local chars = {}
chars.S       = " \t\n\r"              -- S = spaceChar+
chars.NameStart = "A-Za-z:_\128-\255"
chars.Name      = chars.NameStart .. "%-%.0-9"

local tagPat = ('^[^<]*<()([/!%?]?)([Name]*)[S]*().->()'):gsub('%a+', chars)

local attrPat = ("^[S]*([Name]*)[S]*=[S]*(['\"])()"):gsub('%a+', chars)

local closePat = ("^[S]*(/?)>()"):gsub('%a+', chars)


local function SAX(text, fnText, fnStart, fnEnd, fnComm, fnPI)
   local function NoOp() end
   fnText  = fnText  or NoOp
   fnStart = fnStart or NoOp
   fnEnd   = fnEnd   or NoOp
   fnComm  = fnComm  or NoOp
   fnPI    = fnPI    or NoOp
   local maxBuffer = xml.maxBuffer
   local tEmpty = {}
   local pos = 1

   local reader
   if type(text) == "function" then
      reader = text
      text = reader()
   end

   -- These functions are called by the client to get text content.
   local posEnd
   local function getText()
      return decodeText( text:sub(pos, posEnd) )
   end
   local function getCDATA()
      return text:sub(pos, posEnd)
   end


   -- Read more data from the stream.  This may modify `pos` and `text`,
   -- discarding characters that precede `pos`.
   local function more()
      local moreData = reader and reader()
      if moreData then
         assert(#text < maxBuffer, "xml: buffering limit reached")
         text = text:sub(pos) .. moreData
         pos = 1
         return true
      end
      reader = false
   end

   -- Match `pat` in `text`, reading more data as necessary.
   --
   local function matchStream(pat)
      local a, b, c
      repeat
         a, b, c = text:match(pat, pos)
      until a or not more()
      return a, b, c
   end


   -- Parse Attributes at `pos` in `text` and advance `pos` past start tag.
   -- Return table of attributes (name -> value) and boolean (true => this
   -- is an empty element tag).
   --
   local function readAttrs()
      local name, quot, pos2, val, close
      local t = {}

      while true do
         name, quot, pos2 = matchStream(attrPat)
         if not name then
            break
         end
         pos = pos2

         val, pos2 = matchStream("(.-)"..quot.."()")
         assert(pos2, "xml: bad attribute value")
         pos = pos2

         t[name] = decodeText(val)
      end

      close, pos2 = matchStream(closePat)
      assert(pos2, "xml: bad attribute")

      pos = pos2 or #text + 1
      return t, (close ~= "")
   end

   ----------------------
   -- Main loop
   ----------------------

   local pos0, tch, name, pos1, pos2
   while true do

      -- look for "<@(tch)(name) *@.->@" or end of stream  ["@" = pos0/1/2]
      repeat
         pos0, tch, name, pos1, pos2 = text:match(tagPat, pos)
         if pos0 then break end
         pos0 = #text+2
      until not more()

      posEnd = pos0 - 2
      if posEnd >= pos then
         fnText(text, getText)
      end

      pos = pos2
      if tch == "" then

         -- STag or EmptyElemTag

         local attrs = tEmpty
         local bClose
         if pos2 > pos1 + 1 then
            -- something between `name` and ">"
            if pos2 == pos1 + 2 and text:sub(pos1,pos1+1) == "/>" then
               -- empty element tag ending here: no attributes
               bClose = true
            else
               -- parse Attributes & find end of tag
               pos = pos1
               attrs, bClose = readAttrs()
            end
         end
         fnStart(name, attrs)
         if bClose then
            fnEnd(name)
         end

      elseif tch == "/" then

         -- ETag

         fnEnd(name)

      elseif tch == "!" then

         -- Comment or CDATA

         if text:match("^!%-%-", pos0) then
            pos = pos0 + 3
            pos2 = matchStream("%-%->()")
            fnComm(text, pos, pos2 and pos2 - 4 or #text)
            pos = pos2

         elseif text:match("^!%[CDATA%[", pos0) then
            pos = pos0  + 8
            pos2 = matchStream("%]%]>()") or #text+4
            posEnd = pos2 - 4
            fnText(text, getCDATA)
            pos = pos2

         else
            error("xml: unrecognized tag: " .. text:sub(pos0 - 1 , pos0 + 7))
         end

      elseif tch == "?" then

         -- PI
         pos = pos1
         pos2 = matchStream("%?>()") or #text+3
         fnPI(name, text, pos, pos2 - 3)
         pos = pos2

      else
         break  -- end of file
      end
   end
end


function xml.SAX(...)
   return pcall(SAX, ...)
end




-- These special keys are named with "<...>" to avoid colliding with actual
-- XML element names.

xml.MatchTextKey = "<text>"
xml.DefaultKey = "<default>"
xml.ActionKey = "<action>"


-- xml.CaptureText = a map node that captures all text children.
--
-- pattern : string => a pattern applied to *CDATA contents that.  If it
--              matches, the first capture will be retained.
--           true => retain all strings
--           nil => use default pattern (strips leading/trailing spaces)
--
function xml.CaptureText(pattern)
   return {
      [xml.MatchTextKey] = pattern or "^%s*([^%s].-)%s*$"
   }
end


-- xml.CaptureAll = a map node that captures all descendents (text and child
-- elements)
--
function xml.CaptureAll(pattern)
   local t = xml.CaptureText(pattern)
   t[xml.DefaultKey] = t
   return t
end


-- Create a node that captures text from an element that will be "unboxed"
-- (the node's value will be a string, not a table).  All attributes of the
-- node are lost.
--
-- delim = string to place between between children when concatenating.
--
function xml.TextNode(pattern, delim)
   local t = xml.CaptureText(pattern)
   local function action(parent,key,child)
      parent[key] = child[2] and concat(child, delim) or child[1] or ""
   end
   t[xml.ActionKey] = action
   return t
end


function xml.NewAction(node, action)
   local me = {}
   for k,v in pairs(node) do
      me[k] = v
   end

   me[xml.ActionKey] = action
   return me
end


-- xml.ByName returns a new map node equivalent to the input node, except
--     that it will be stored at parent[<elementName>] (not as a new array
--     element at parent[<nextIndex>]).
--
function xml.ByName (node)
   local oldaction = node[xml.ActionKey] or rawset

   local function action(parent,key,child)
      return oldaction(parent,child._type,child)
   end
   return xml.NewAction(node, action)
end


-- xml.ListByName returns a new node equivalent to the input node, except
--     that each occurrence of the element appends its results to an array
--     of values stored at parent[<elementName>].
--
function xml.ListByName (node)
   local oldaction = node[xml.ActionKey] or rawset

   local function action (parent,key,child)
      key = child._type
      local list = parent[key]
      if type(list) ~= "table" then
         list = {}
         parent[key] = list
      end
      return oldaction(list,#list+1,child)
   end
   return xml.NewAction(node, action)
end


-- xml.STRING : this node describes an element that appears once in its
--       parent element and contains a string.  It will appear as a
--       named field in the document tree with a string value.  Leading
--       and trailing spaces are omitted.
--
xml.STRING = xml.ByName( xml.TextNode() )

-- this replaces the chained action with a faster equivalent
xml.STRING[xml.ActionKey] = function(t,k,v)
                               t[v._type] = v[2] and concat(v) or v[1] or ""
                            end


xml.STRING_LIST = xml.ListByName( xml.TextNode(nil, "\n") )


-- xml.numberNode : this node describes an element that contains an
--    ASCII-encoded number.
--
xml.numberNode = {
   [xml.MatchTextKey] = true,
   [xml.ActionKey] = function (t,k,v) t[k] = tonumber(v[1]) end
}

-- xml.NUMBER : this node describes an element that appears once in its
--       parent element and contains a number.  It will appear as a
--       named field in the document tree with a number value.
--
--       This is equivalent to xml.ByName( xml.numberNode ) but faster.
--
xml.NUMBER = {
   [xml.MatchTextKey] = true,
   [xml.ActionKey] = function(t,k,v) t[v._type] = tonumber(v[1]) end,
}

xml.NUMBER_LIST = xml.ListByName( xml.numberNode )


-- xml.ERROR : this node describes an element that is not expected.  If any
--    element is encountered at this node, an error will be issued.
--
xml.ERROR = {
   [xml.ActionKey] = function (t,k,v) error("xml: unexpected node: "..v._type) end
}


-- xml.DOM(text, [map])
--
-- text = XML to parse (as in xml.SAX)
-- map = description of elements to capture (see above)
--       Defaults to xml.CaptureAll.
--
-- On success:  returns DOM tree
-- On error:    returns nil, message
--
function xml.DOM(text, map)
   local matchAnyElem = xml.DefaultKey
   local matchText    = xml.MatchTextKey
   local actionKey    = xml.ActionKey

   local root = { }            -- root result node
   local mapStack  = {}        -- stack of map nodes we've descended into
   local nullMap = {}          -- value for map when we are 'off the map'
   local node = root           -- current map node
   local deep = 0              -- number of levels deeper than the map
   local parent = {}
   setmetatable(parent, { __mode = "k" })

   map = map or xml.CaptureAll()

   local function Start(elem, attrs)
      if deep > 0 then
	 deep = deep + 1
	 return
      end

      insert(mapStack, map)
      map = map[elem] or map[matchAnyElem]
      if map then
	 -- deeper in map
	 local newNode = {
	    _type = elem,
	 }
         parent[newNode] = node
	 for k,v in pairs(attrs) do
	    newNode[k] = v
	 end
	 node = newNode
      else
	 -- leaving the map; ignore everything
	 deep = 1
         map = nullMap
      end
   end

   local function End(elem)
      if deep > 0 then
	 deep = deep - 1
         if deep == 0 then
            map = remove(mapStack)
         end
      else
         local child = node
         node = parent[node]
         local action = map[actionKey]
         if action then
            action(node, #node+1, child)
         else
            node[#node+1] = child
         end
         map = remove(mapStack)
      end
   end

   local function Text(data, getit)
      local pat = map[matchText]
      if pat then
         local txt = getit()
         local cap = pat==true and txt or txt:match(pat)
         if cap then
            insert(node, cap)
         end
      end
   end

   local function Comment(txt, a, b)
      local action = map[actionKey] or rawset
      if action then
         action(node, #node+1, { _type = "_comment", txt:sub(a,b) })
      end
   end

   local function PI(name, txt, a, b)
      local action = map[actionKey] or rawset
      if action then
         action(node, #node+1, { _type = "_pi_"..name, txt:sub(a,b) })
      end
   end

   local succ, err = xml.SAX(text, Text, Start, End, Comment, PI)
   if not succ then
      return nil, err
   end

   while mapStack[1] do
      End()
   end

   return root
end


return xml
