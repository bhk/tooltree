-- htmlgen:  Generate HTML 4.0 from a document tree (see doctree.lua)
--
--
-- htmlgen.normalize(inTree, [options]) --> outTree
--
--     Return a new document tree with a normalized structure:
--
--      * One `html` element at the top of the tree.
--      * One `head` and one `body` under the `html` element.
--      * Exactly one `title` element under `head`.
--
--     The resulting `head` contains all the children of `head` elements in
--     `inTree`.
--
--     The resulting `body` contains all *other* nodes in the tree with the
--     exception of node._type == nil or `html` or `body`, which are
--     flattened (replaced by their children).
--
--     This does not modify the input tree. `outTree` will reference nodes
--     in `inTree`.
--
--     *Idempotent nodes*: When head nodes have a `_once` property, at most
--     one (the first) will be included for each distinct value of `_once`.
--     Nodes of type "title" implicitly have a `_once` value of "title".
--
--     `options` is a table (defaulting to an empty table). If
--     `options.charset` contains anything other than `false`, a `meta`
--     element describing the charset will be added to the resulting data
--     structure.  If it contains a string, that will be used as the charset
--     (otherwise "utf-8" is assumed).
--
--
-- htmlgen.serialize(tree, [options])  -->  text
--
--     Generate HTML from a document tree.
--
--     In the case of element names that are defined in the HTML 4.0
--     specification, test content will be properly encoded (as per the
--     content type defined for that element), and empty elements will
--     generate open tags (without close tags).
--
--     Nodes with a tag name of `_html` are treated as containing raw
--     HTML. All string contents will be output without any encoding.
--
--     Every node with a tag names that do not begin with "_" will be output
--     as an element (enclosed in open and close tags). If the tag name is
--     not described in HTML 4.0, it will be treated a non-empty PCDATA
--     elements.
--
--     The following node fields affect the behavior of `serialize`:
--
--      * `_isEmpty`: causes a non-HTML 4.0 element to be output without
--        a close tag.
--
--      * `_whitespace`: if true, contained whitespace will be serialized
--        literally (newlines will not be inserted for readability).
--
--     The resulting text is encoded in UTF-8. It is assumed that all
--     strings in the input tree contain UTF-8-encoded text.
--
--     If an error condition is detected, `errfn(desc)` will be called, with
--     `desc` describing the error. This function may throw an error to
--     abort processing, or return to have the error silently ignored.
--
--      * `"CDATA encode"` indicates that a CDATA cannot be successfully
--        encoded because its text content includes the string `"</"`.
--        (CDATA is incapable of representing such a substring.)  The
--        default action is to encode `"</"` as `"<\\/"`, which would
--        probably produce the desired behavior when the substring occurs
--        within a literal string in JavaScript code within a `script`
--        element.
--
-- TODO: _type==_comment
--
-- htmlgen.generateDoc(tree, options)  -->  html
--
--     This is equivalent to:
--
--        htmlgen.serialize(htmlgen.normalize(tree, options), options)
--
--

local Object = require "object"
local utf8utils = require "utf8utils"
local doctree = require "doctree"
local opairs = require "opairs"

local insert, concat = table.insert, table.concat
local E, TYPE = doctree.E, doctree.TYPE

----------------------------------------------------------------
-- Serialization of HTML
----------------------------------------------------------------

local htmlSubs = {
   ["<"] = "&lt;",
   [">"] = "&gt;",
   ["&"] = "&amp;",
   ['"'] = "&quot;"
}

local function badUTF8(n)
   return 0xFFDD;
end

local function makeCharRef(ch)
   return ("&#%d;"):format(utf8utils.decode(ch, badUTF8))
end

local function htmlEscape(str)
   return (str:gsub("[<>&]", htmlSubs):gsub(utf8utils.mbpattern, makeCharRef))
end

local function htmlEscapeAttr(str)
   return (str:gsub('[>&"]', htmlSubs))
end


local function encodeAttrs(node)
   local ta = {""}
   for k, v in opairs(node or {}) do
      if v and type(k) == "string" and k:sub(1,1) ~= "_" then
         local a = k
         if v ~= true then
            a = k .. '="' .. htmlEscapeAttr(tostring(v)) .. '"'
         end
         insert(ta, a)
      end
   end
   return ta[2] and concat(ta, " ") or ""
end

-- empty elements do not have close tags
--
local elemIsEmpty = {
   area = true,
   base = true,
   br = true,
   col = true,
   hr = true,
   img = true,
   input = true,
   link = true,
   meta = true,
   param = true,
   -- proposed HTML5 tags
   command = true,
   embed = true,
   keygen = true,
   source = true,
   track = true,
   wbr = true,
}


-- Some block-level elements are emitted with newlines after/before
-- open/close tags for readability.
--
-- HTML specifications state that newlines must always be ignored after open
-- tags and before close tags (as per SGML).  Unfortunately, Safari, Chrome,
-- and Firefox do not honor this rule, as is apparent in the following case:
--
--    <p style="white-space:pre; border: 1px solid blue; padding: 0">
--    text
--
--    </p>
--
-- This results in blank lines before and after 'text'.  Changing the 'p'
-- element to a 'pre' removes the first blank line -- as if there is a
-- special case for 'pre' in parsing or rendering.
--
-- As a result, we emit this additional whitespace only in certain cases,
-- and allow doctree nodes to override this by setting their '_whitespace'
-- field to true.
--
local elemIsBlock = {
   address = true,
   blockquote = true,
   -- div = true,
   h1 = true,
   h2 = true,
   h3 = true,
   h4 = true,
   h5 = true,
   h6 = true,
   p = true,
   -- pre = true,
   ol = true,
   ul = true,
   li = true,
   hr = true,
   html = true,
   body = true,
   head = true,
   meta = true,
   style = true
}


local elemIsCDATA = {
   style=true,
   script=true
}


local HTMLGen = Object:new()


function HTMLGen:initialize(options)
   self.options = options or {}
end


function HTMLGen:warn(node, ...)
   local warn = self.options.warn
   if warn then
      warn(node, string.format(...))
   end
end


function HTMLGen:append(str)
   insert(self.strings, str)
end


function HTMLGen:serializeNode(node)
   if type(node) == "string" then
      self:append(htmlEscape(node))
      return
   elseif type(node) ~= "table" then
      self:warn("Unrecognized node type: %s", type(node))
      return
   end

   local name = node[TYPE]

   if name and name:sub(1,1) == "_" then
      -- special nodes

      if name == "_html" then
         for _, chile in ipairs(node) do
            self:append(chile)
         end
      end
      return
   end

   -- construct open/close tags
   local o,c = "", ""
   if name then
      local nl = (elemIsBlock[name] and not node._whitespace) and "\n" or ""
      local attrs = encodeAttrs(node)
      o = string.format("<%s%s>%s", name, attrs, nl)
      if not (elemIsEmpty[name] or node._isEmpty) then
         c = string.format("%s</%s>", nl, name)
      end
   end

   self:append(o)

   if elemIsCDATA[name] then
      local text = doctree.treeConcat(node)
      if text:match("</") then
         self:warn(node, "Invalid content for CDATA element %s: '</'", name)
         -- As a last resort, use an encoding that works when the "</"
         -- occurs in a string in JavaScript
         text = text:gsub("</", "<\\/")
      end
      self:append(text)
   else
      for _,child in ipairs(node) do
         self:serializeNode(child)
      end
   end

   self:append(c)
end


-- The following verbosity is unfortunately part of W3C's HTML4 spec.  When
-- a document omits this or similar DOCTYPE crud, Internet Explorer 8 will
-- incorrectly report that the document contains "dangerous" ActiveX or
-- scripting.  The proposed HTML5 specification reduces this to a simple
-- "<!DOCTYPE HTML>", so we can hope for a better future.
--
local htmlPreamble = [[
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
]]


function HTMLGen:serialize(tree)
   assert(self ~= HTMLGen)

   self.strings = { htmlPreamble }

   self:serializeNode(tree)
   self:append("\n")
   return concat(self.strings)
end


----------------------------------------------------------------
-- Normalization of HTML
----------------------------------------------------------------


-- See documentation for `htmlgen.normalize()`, above.
--
function HTMLGen:normalize(tree)
   local head = E.head{}
   local body = E.body{}
   local seen = {}

   local function appendToHead(child)
      if type(child) == "table" then
         local seenkey = child._once or (child[TYPE] == "title" and "title")
         if seenkey then
            if seen[seenkey] then return end
            seen[seenkey] = true
         end
      end
      table.insert(head, child)
   end

   local function visit(node, tbl)
      if type(node) ~= "table" then
         table.insert(tbl, node)
         return
      end

      local ty = node[TYPE]

      if ty == "head" then
         for _, child in ipairs(node) do
            appendToHead(child)
         end
         return
      end

      local o = tbl
      if ty and ty ~= "html" and ty ~= "body" then
         -- clone attributes of `node` to new node
         o = {}
         for k, v in pairs(node) do
            if type(k) ~= "number" then
               o[k] = v
            end
         end
         table.insert(tbl, o)
      end

      for _, child in ipairs(node) do
         visit(child, o)
      end
   end

   local charset = self.options.charset
   if charset ~= false then
      if type(charset) ~= "string" then
         charset = "utf-8"
      end
      appendToHead( E.meta { ["http-equiv"]="Content-Type",
                             content="text/html;charset=" .. charset } )
   end

   visit(tree, body)

   appendToHead( E.title{} )

   return E.html {
      head, body
   }
end


----------------------------------------------------------------
-- exported functions
----------------------------------------------------------------

local htmlgen = {}

function htmlgen.generateDoc(tree, options)
   local hg = HTMLGen:new(options)
   return hg:serialize( hg:normalize(tree) )
end

function htmlgen.serialize(tree, options)
   return HTMLGen:new(options):serialize(tree)
end

function htmlgen.normalize(tree, options)
   return HTMLGen:new(options):normalize(tree)
end

htmlgen.HTMLGen = HTMLGen -- for testing

return htmlgen
