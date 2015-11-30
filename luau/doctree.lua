-- doctree: Document tree utilities
--
-- Document Trees
-- ==============
--
-- A "document tree" is a structure representing HTML or XML document
-- content.
--
--  * String values represent text content.
--
--  * An HTML/XML element is represented by an Lua table with the tag name
--    stored in under the key `"_type"`. Attributes are stored in the table
--    under the attribute name. For example, the following describes a link:
--
--        { _type="a", href="foo.html", "Foo"}
--
--  * Tables may also be used as simple arrays containing other document
--    tree nodes.  (No open or close tages will be emitted in this case.)
--
-- Attribute names beginning with `_` will be ignored unless otherwise
-- specified.  For example, `_type` is used to store the tag name.
--
-- Tag names that begin with `_` are special. Tables with such tag names
-- will be treated as simple arrays (unless otherwise specified). For
-- example, `_html` is recognied by `htmlgen.lua` as containing raw HTML.
--
--
-- Usage
-- =====
--
-- doctree.E[tagName]  -->  function [table -> node]
--
--     Generate an element constructor, given a tag name.  E is a table that
--     can also be used as a function. The constructor functions are created
--     on-demand and memoized.
--
--     For example:
--
--        `doctree.E.pre({"hello"})` returns `{_type="pre", "hello"}`.
--
-- treeConcat(a)  -->  string
--
--     Concatenate all strings that desecned from array `a`.
--
-- visitElems(tree, fn, [type])
--
--     Call `fn(node)` once for every element node in `tree`.  If `type` is
--     non-nil, only nodes whose `_type` field equals `type` will be visited.
--     If `type` is nil, visit every table whose `_type` field is a string.
--

local memoize = require "memoize"


-- This is the key under which each node's element type/name is stored.
--
local TYPE = "_type"


-- E : E(name) returns a constructor of nodes of type 'name'.
--
local E = memoize.newTable(function (e) return function (t) t._type = e; return t end end)


-- Retrieve the textual content of a node (including all sub-tables) as one
-- string.
--
local function treeConcat(tree)
   local o = {}

   local function fc(node)
      if type(node) == "table" then
         for _, child in ipairs(node) do
            fc(child)
         end
      else
         table.insert(o, tostring(node))
      end
   end

   fc(tree)
   return table.concat(o)
end


local function visitElems(node, f, ofType)
   if type(node) == "table" then
      if ofType == node._type or not ofType and type(node._type) == "string" then
         f(node)
      end
      for n = 1, #node do
         visitElems(node[n], f, ofType)
      end
   end
   return node
end


return {
   E = E,
   TYPE = TYPE,
   treeConcat = treeConcat,
   visitElems = visitElems
}
