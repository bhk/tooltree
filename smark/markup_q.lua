local qt = require "qtest"
local doctree = require "doctree"
local utf8utils = require "utf8utils"
local Source = require "source"
local testsource = require "testsource"

local mu = require "markup"  -- make this a dependency (and dry run compilation)

local mu, _mu = qt.load("markup.lua", {
                           "linePEG",   "parseInline", "parseLayout",
                           "expandDoc", "formatParg",  "macros",
                           "markupDoc", "markAnchors", "genTOC"
                        })

local eq = qt.eq

local E, TYPE = doctree.E, doctree.TYPE

local errors
local function newSource(str)
   local src = testsource.new(str)
   errors = src.errors
   return src
end

local function parseLayoutString(str) return _mu.parseLayout(newSource(str)) end
local function parseInlineString(str) return _mu.parseInline(newSource(str)) end
local function parseDocString(str) return mu.parseDoc(newSource(str)) end

----------------------------------------------------------------
-- linePEG: parse list tag & indentation for one line
----------------------------------------------------------------

local function tagTest(a,b)
   local str = b.."  Item\n"
   local posTag, tag, posText, text, posEnd = _mu.linePEG:match(str)

   qt._eq(1, posTag, 2)
   qt._eq(a, tag, 2)
   eq(str:sub(posText, posText + #text - 1), text)
   if tag == "" then
      eq(1, posText)
   else
      eq("Item", text)
   end
   eq(#str, posEnd)

   str = b.."---"
   posTag, tag, posText, text, posEnd = _mu.linePEG:match(str)
   eq(1, posTag)
   eq("", tag)
   eq(1, posText)
   eq(str, text)
end
tagTest("-", "-")
tagTest("1", "#.")
tagTest("A", "A)")
tagTest("a", "a)")
tagTest("1","3.")
tagTest("", "3:")
tagTest("1","10.")
tagTest("a","aa)")

----------------
-- parseLayout
----------------

local function xform(node, src)
   for ndx,c in ipairs(node) do
      if type(c) == 'table' then
         xform(c, src)
      else
         local a, b = src:find(c.."\n", 1, true)
         node[ndx] = {a,b}
      end
   end
   return node
end


local slSample = [[
First
=====
  Sec&nd
  1. line1
     line1.2
      * bullet
  2. line2
]]

local t = xform( {
   i=0,
   "First",
   "=====",
   {
      i=2,
      "Sec&nd",
      {
         i=4.5, tag="1", tagi=2,
         {
             i=5,
            "line1",
            "line1.2",
            {
               i=7.5, tag="*", tagi=6,
               { i=8, "bullet" },
            },
         },
         { "line2", i=5 },
      }
   }
}, slSample)


local lnode = parseLayoutString(slSample)
eq(t, lnode)

-- check event cascade & position calculation


-- expect warning for tag without paragraph

parseLayoutString(" 1.  \n")
eq({{'ignoring list tag "1." with empty paragraph', 2}}, errors)


----------------
-- inline
----------------

local function rmSource(tree)
   local function rm(t)
      t._source = nil
      t.expand = t.expand and true
   end
   doctree.visitElems(tree, rm)
   return tree
end

local function tm(t,s,w)
   local o, extra = parseInlineString(s)
   qt._eq(nil, extra, 2)
   o = rmSource(o)

   qt._eq(t, o, 2)

   if w then
      qt.match(qt.describe(errors[1]), qt.describe(w))
   else
      qt._eq({}, errors, 2)
   end

   local o2 = parseInlineString(s:gsub(" ","\n"))
   o2 = rmSource(o2)
   qt._eq(o, o2, 2)
end


-- ## parseInline() processes a paragraph, extracting inline markup structure.

tm( {"abc"},         "abc")

-- ## Inline character references are replaced.

tm( {"AT&T"},        "AT&amp;T")
tm( {"AT&T"},        "AT&T")
tm( {"\226\134\146\226\134\144"},   "&rarr;&#x2190;" )
tm( {"a &b; c"},     "a &b; c",      {"unrecognized entity.*",3})
tm( {"a &#ax; c"},   "a &#ax; c",    {"unrecognized entity.*",3})

-- ## Special characters

local e = utf8utils.encode
local specials = {
   ['""'] = e(0x201c) .. e(0x201D),
   ['--'] = e(0x2014),
   ['<--'] = e(0x2190),
   ['-->'] = e(0x2192),
   ['<=='] = e(0x21D0),
   ['==>'] = e(0x21D2),
}
local str = '"" --> <-- ==> <== --'
tm( {(str:gsub('[^ ]+',specials))},   str )


-- ## Pairs of (one or more '`') quotes code.  Within code quotes, all
--    characters are literal except matching close sequence.

tm( {E.code{"TXT"}},         "`TXT`")
tm( {E.code{"TXT"}},         "``TXT``")
tm( {E.code{"T``*b*`\\"}},   "```T``*b*`\\```")

-- ## First space after/before open/close backquote symbol is ignored.

tm( {E.code{"A Z "}},         "`` A Z  ``")
tm( {E.code{" ` "}},         "``  `  ``")

-- ## Pairs of '**' or '*' "marks" enclosing words indicate <b> & <i>.

tm( {E.i{"e"}},              "*e*")
tm( {"a",E.i{"b*c"},"d"},    "a*b\\*c*d")
tm( {"x ",E.b{"b"},"yy"},    "x **b**yy")
tm( {"**bold**"},                  "\\*\\*bold\\*\\*" )


-- ## '_' and '__' are no longer treated as markup.

tm( {"IFoo_Func"},                  "IFoo_Func")


-- ## Nesting: inline markup sequences can nest within other markup
--      sequences, except: (a) not within equivalent markup, (b) nothing
--      within <code>.

tm( {E.i{"a",E.code{"b"},"c"}},   "*a`b`c*")
tm( {E.i{"ab",E.b{"cd"},"ef"}},   "*ab**cd**ef*" )
tm( {E.b{"ab",E.i{"cd"},"ef"}},   "**ab*cd*ef**" )


--   ## Open 'mark' cannot precede a space, and close 'mark' cannot follow a
--      space.  If surrounded by spaces, literal.  Otherwise, warn.

tm( {"a * b ** c"},        "a * b ** c")
tm( {'(`)'},               '(`)',       {"unbalanced.*",2} )
tm( {"a *b"},              "a *b",      {"unbalanced.*%*",3} )
tm( {"a* b c*"},           "a* b c*",   {"unbalanced.*%*",2} )
tm( {"a *b *c"},           "a *b *c",   {"unbalanced/unescaped.* %*",3} )

-- ## Match "|" in text. [Bug fixed when legacy URL syntax was removed.]

tm( {"a | b || c"},       "a | b || c")


--  ## Invalid UTF-8 sequences generate warnings and are treated as ISO-Latin-1

tm( {"a"..utf8utils.encode(169).."b"},  "a"..string.char(169).."b",  {"invalid.*",2} )


-- ## A single backslash can be used to escape any punctuation character.
--    [Markdown: only for \ ` * _  {} [] () # + - . ! ]

tm( { [[!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~*`]] },
    [[\!\"\#\$\%\&\'\(\)\*\+\,\-\.\/\:\;\<\=\>\?\@\[\\\]\^\_\`\{\|\}\~\*\`]] )


-- ##  [[ link ]]  and  [[ text | link ]]

local function L(link, ...) return E._object{ link=link, expand=true, ...} end
local function H(href, ...) return E.a{ href=href, ...} end


tm( { L("text", "text") },    "[[text]]")
tm( { "a",L("b", "b") },      "a[[b]]")
tm( { L("text", "text") },    "[[  text  ]]")
tm( { L("x]", "x]") },        "[[x\\]]]")
tm( { "a", L("b", "b"),"c" }, "a[[b]]c")

tm( {"]]"},         "]]")

tm( { L("text", "t", E.code{ "ex"},"t") },    "[[t`ex`t]]")

--tm( {"see ", H('c d', 'a b'), ","}, 'see [[a b|c d]],')
--tm( {"see ", H('c d', 'a b'), ","}, 'see [[a b | c d]],')
--tm( {"see ", H('c d', 'a b'), ","}, 'see [[ a b  |  c d ]],')

-- ## link characters are literal

--tm( {"see ", H('c*d', 'a b'), ","}, 'see [[ a b  |  c*d ]],')

-- TODO: what is appropriate here:
-- tm({" ****"}, " **** ")

-- ## [text](url "Title")

tm( {E.a{href="url","text"}},            "[text](url)")
tm( {E.a{href="uri",title="tl","xx"}},   '[xx] ( uri "tl" )')
tm( {E.a{href="uri",title="tl","xx"}},   '[ xx ] ( uri "tl" )')
tm( {"[a ",E.a{href="url","text"}},      "[a [text](url)")
tm( {E.a{href="url","a",E.i{"b"},"c"}},   "[a*b*c](url)")

-- ## HREF normalization.

tm( {E.a{href="a%20b","text"}},            "[text](a b)")

-- ## [xxx](@anchorname)

tm( {E.a{name="anchor","xxx"}},          "[xxx] (@anchor)")

-- ## [[@anchortext]]

tm( {E.a{name="anchor","anchor"}},       "[[@anchor]]")


-- ## <http://...>

tm( {E.a{href="http://xx","http://xx"}},   "<http://xx>")


-- ## Newlines same as spaces (generally)

tm( {"this is a test"},    "this\nis\na\ntest" )

-- ## Line break indicated by "\" at end of line

tm( {"one ", E.br{}, "two ",E.br{}},     "one  \\  \n two   \\")


-- ## Nested markup.

tm({E.a{href="uri","a",E.i{"b"},"c"}},  "[a*b*c](uri)")
tm({E.i{E.a{href="uri","abc"}}},  "*[abc](uri)*")


-- ## Inline macros

tm({E._macro{text="arg", macro="foo"},"x"},   "\\foo{arg}x" )


tm({E._macro{text="a{}b", macro="foo"},"x"},   "\\foo{a{}b}x" )


-- Other markdown:
--   ## [text][id]
--   ## <name@address.com>
--   ## "> xxx" (email-style indenting)
--   !! Undesirable: "**" may be interpreted as a "*" beginning bold-face, as in:
--          ** x**    -->   <i>* x</i>*
--          ** x **   -->   <i>* x *</i>

----------------
-- formatParg
----------------


eq(E.pre{" abc\ndef\n ghi\n x"},
   _mu.formatParg( parseLayoutString".  abc\n. def\n.  ghi\n.  x", 1, 4))


eq(E.hr{}, _mu.formatParg( parseLayoutString "---", 1, 1) )
eq(E.hr{}, _mu.formatParg( parseLayoutString "-=-=-=-", 1, 1) )


----------------
-- markupDoc
----------------

local function mkup(...)
   return rmSource( _mu.markupDoc(...) )
end

eq({E.h3{"hdr"}}, mkup( parseLayoutString "hdr\n---\n") )

local txt1 = [[
a
b
 1. item
c
]]
local doc1 = {
   E.p {"a b"},
   E.ol {
      type="1",
      E.li { E.p{"item"} },
   },
   E.p {"c"}
}
eq( doc1, mkup( parseLayoutString(txt1) ) )


local txt2 = [[
aaa
    qqq
]]
local doc2 = {
   E.p{"aaa"},
   E.div{ class = "indent",
          E.p{ "qqq" } },
}
eq( doc2, mkup( parseLayoutString(txt2) ))


----------------------------------------------------------------
-- parsing macros
----------------------------------------------------------------

local function _parseDoc(...)
   return rmSource( parseDocString(...) )
end

local txt = [[
.m0
   BB
   CC

.

.m1: ARG

.m2
  * li1

]]

eq( { E._macro{text="BB\nCC\n", macro="m0"},
      E._macro{text="ARG\n", macro="m1"},
      E._macro{text="* li1\n", macro="m2"}
    },
    _parseDoc(txt))

-- ## .end <macro>

local txt = [[
.m1
   BB
.end m1
]]

eq( { E._macro{text="BB\n", macro="m1"} },
    _parseDoc(txt))

qt.runTests()


----------------------------------------------------------------
-- macros
----------------------------------------------------------------


_mu.macros["nil"] = function () return nil end

local t = _mu.expandDoc( E.div{
                        E._macro{macro="nil", text=""},
                        E.p{"paragraph"} } )

eq( E.div{ E.p{"paragraph"}, class="smarkdoc" },  t)



-- expand objects with renderHTML method

--local t = _mu.expandDoc( E.div{
--                        E._object{ renderHTML = function () return E.br{} end },
--                        "a"
--                     } )
--
--eq(E.div{ E.br{}, "a" }, t)


-- order of expansion



local counter = 0
local function next(str)
   return function ()
             counter = counter + 1
             return str .. tostring(counter)
          end
end

local t = E.div {
   E._object{ expand = function (node, doc)
                          return E._object { expand = next "a" }
                      end },
   E._object{ expand = next "b" },
}

eq(E.div{ "a1", "b2", class="smarkdoc" },   _mu.expandDoc(t))


-- Every "_defer" should be unwrapped at the next cycle.  Each pass should
-- expand macros and their resulting "_object" results exactly once.

-- Bug fix: Objects returning a non-special node would get doubly-expanded.

local t = E.div {
   E._defer{ E._object { expand = next "a" } },

   E._object { expand = function ()
                           return { E._defer { E._object { expand = next "b" } } }
                        end },

   E._object{ expand = next "c" },
}

counter = 0
eq(E.div{ {"a2"}, {{"b3"}}, "c1", class="smarkdoc" },   _mu.expandDoc(t))


----------------------------------------------------------------
-- Anchors and TOC
----------------------------------------------------------------

local function tocTest(docIn, tocOut)
   local a = _mu.markAnchors({ top=docIn })
   local o = _mu.genTOC(docIn, {top=docIn, anchors=a})
   return eq(tocOut, o)
end

tocTest(
   E.div {
      E.h1 { "Header1" },
      E.p { "Some text" },
      E.h2 { "Header" },
      E.h3 { "Header" },
      E.h1 { "H1_2" },
   },
   E.div {
      class ="toc",
      E.div {
         class ="tocLevel",
         E.a { href = "#Header1", "Header1"},
         E.div {
            class ="tocLevel",
            E.a { href = "#Header", "Header"},
            E.div {
               class ="tocLevel",
               E.a { href = "#_Header", "Header"} } } },
      E.div {
         class ="tocLevel",
         E.a { href = "#H1_2", "H1_2"} },
   })


-- bug: single H2 => H2 link is not enclosed in tocLevel
tocTest(E.div {
           E.p{ "test" },
           E.h2{ "H2" },
           E.h3{ "H3" },
        },
        E.div {
           class = "toc",
           E.div {
              class = "tocLevel",
              E.a { href="#H2", "H2" },
              E.div {
                 class = "tocLevel",
                 E.a { href = "#H3", "H3" },
              }
           }
        })


-- missing levels
tocTest(E.div {
           -- no H1s => level removed
           E.h2{ "H2" },
           -- empty H3 level
           E.h4{ "H4" },
           E.h3{ "H3" },
        },
        E.div {
           class = "toc",
           E.div {
              class = "tocLevel",
              E.a { href="#H2", "H2" },
              E.div {
                 class = "tocLevel",
                 E.div {
                    class = "tocLevel",
                    E.a { href = "#H4", "H4" },
                 },
              },
              E.div {
                 class = "tocLevel",
                 E.a { href = "#H3", "H3" }
              }
           }
        })



----------------------------------------------------------------
-- Links
----------------------------------------------------------------

local tree = parseDocString [==[
[[A B]]

A B
===

[A.B] (#A B)
]==]

tree = _mu.expandDoc(tree)

local links = {}
doctree.visitElems(tree,
                function (node)
                   node._source = nil
                   table.insert(links, node)
                end,
                "a")

eq({
      {[TYPE]="a", "A B", href="#A%20B"},
      {[TYPE]="a", name="A%20B"},
      {[TYPE]="a", "A.B", href="#A%20B"},
   },
   links)

----------------------------------------------------------------
-- doc:warn
----------------------------------------------------------------

_mu.expandDoc {
   _source = newSource(""),
   E._object {
      expand = function (node, doc)
                  doc:warn(node, 0, "W%s", "A%s", "B")
               end
   }
}

eq({{"WA%s", nil, nil}}, errors)

