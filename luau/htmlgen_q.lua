local qt = require "qtest"
local doctree = require "doctree"
local htmlgen = require "htmlgen"

local E = doctree.E


----------------------------------------------------------------
-- serialize
----------------------------------------------------------------

local smallDoc = E.div {
   E.p {"a<b&c>d"},
   -- HR is an empty element
   E.hr {},
   -- output attribute with special characters
   E.a {"a b", href = 'c " d'},
   -- "</" is not encodable in CDATA. Default is to assume it occurs in a
   -- JavaScript string or comment.
   E.script { "x</y" },
}

local smallHTML = [[
<div><p>
a&lt;b&amp;c&gt;d
</p><hr>
<a href="c &quot; d">a b</a><script>x<\/y</script></div>
]]

local o = htmlgen.serialize(smallDoc)
qt.match(o, "^<!DOCTYPE")
qt.eq(o:gsub("<!DOCTYPE[^>]*>\n", ""), smallHTML)


----------------------------------------------------------------
-- dumpHTML
----------------------------------------------------------------

local gh1_in = E.div{
   class = "smarkdoc",
   E.h1 {"A&B"},
   E.p { "a", E.i{"b"}, "c" },
   E.head { E.title { "A&B" } },
}

local gh1_out = [[
<html>
<head>
<meta content="text/html;charset=utf-8" http-equiv="Content-Type">
<title>A&amp;B</title>
</head><body>
<div class="smarkdoc"><h1>
A&amp;B
</h1><p>
a<i>b</i>c
</p></div>
</body>
</html>
]]

local o = htmlgen.generateDoc(gh1_in)
qt.match(o, "^<!DOCTYPE")
qt.eq(o:match("<!DOCTYPE.->\r?\n?(.*)"), gh1_out)


----------------------------------------------------------------
-- Normalize
----------------------------------------------------------------

qt.eq( htmlgen.normalize({}, { charset=false }),
       E.html { E.head{ E.title{} }, E.body{} })


qt.eq( htmlgen.normalize(E.div{"hi", E.head{ E.title{"A"}}}, {charset=false}),
       E.html { E.head{E.title{"A"}}, E.body{E.div{"hi"}} })


qt.eq( htmlgen.normalize( E.html{ E.head{ E.title{"A"}}, E.body{"hi"} },
                          {charset=false} ),
       E.html{ E.head{ E.title{"A"}}, E.body{"hi"} })

