-- xml_q.lua

local qt = require "qtest"
local xml = require "xml"

local eq = qt.eq

function qt.tests.decodeText()
   local decodeText = xml._decodeText

   eq("ABC", decodeText("A&#66;C"))
   eq("ABC", decodeText("A&#066;C"))
   eq("ABC", decodeText("A&#x42;C"))
   eq("ABC", decodeText("A&#x042;C"))

   eq("A&B", decodeText("A&amp;B"))
end


local xlAttrs


-- Translate an XML object to a simple string representation
local function xl(t)
   if type(t) == "string" then
      return "(" .. t .. ")"
   elseif type(t) == "table" then
      local strings = {}
      for _,val in ipairs(t) do
         table.insert(strings, xl(val))
      end
      return "{" .. (t._type or "") .. xlAttrs(t) .. table.concat(strings) .. "}"
   elseif type(t) == "number" then
      return "#"..tostring(t)
   end
end


function xlAttrs(t)
   local strings = {}
   for name,val in pairs(t) do
      if type(name) == "string" and name ~= "_type" then
         table.insert(strings, ";"..name.."="..xl(val))
      end
   end
   table.sort(strings)  -- sort attributes for predictable output
   local str = table.concat(strings)
   return str..":" --str ~= "" and str..":" or str
end


-- Parse XML, generating simple text representation
--
local function xlSAX(text)
   local str = ""
   local function Text (data, getit)
      str = str .. "(" .. getit() .. ")"
   end
   local function Open(elem, t)
      str = str .. "{" .. elem .. xlAttrs(t)
   end
   local function Close (elem)
      str = str .. "}" .. elem
   end
   local function Comment(data,a,b)
      str = str .. "<" .. data:sub(a,b) .. ">"
   end
   local function PI(name, data, a, b)
      str = str .. "{?" .. name .. " " .. data:sub(a,b) .. "}"
   end

   local succ, err = xml.SAX(text, Text, Open, Close, Comment, PI)
   if not succ then
      print("error: " .. err)
      print("   in: " .. text)
   end
   return str
end


function qt.tests.SAX()
   local x

   x = xlSAX('data')
   eq("(data)", x)

   x = xlSAX('<a></a>')
   eq("{a:}a", x)

   x = xlSAX('<A/><_AZaz09:/>')
   eq("{A:}A{_AZaz09::}_AZaz09:", x)

   x = xlSAX('<a>data</a>')
   eq("{a:(data)}a", x)

   x = xlSAX('pre<a>a1<b>btext</b> a3 <c>cdata</c></a>post')
   eq("(pre){a:(a1){b:(btext)}b( a3 ){c:(cdata)}c}a(post)", x)

   x = xlSAX('<a n1="v1"  n2 =" v2" n3= \'v3\'>a cdata</a>')
   eq("{a;n1=(v1);n2=( v2);n3=(v3):(a cdata)}a", x)

   x = xlSAX('<a b=\'y>x\' c= "j>i" d="\'"> v>u  </a>')
   eq("{a;b=(y>x);c=(j>i);d=('):( v>u  )}a", x)

   x = xlSAX('pre<![CDATA[ is <cdata> &amp; foo]]>post')
   eq("(pre)( is <cdata> &amp; foo)(post)", x)

   x = xlSAX('<!-- a > b < c -->')
   eq('< a > b < c >', x)

   x = xlSAX('<!-- c1 x="y"--><a>j<!--c2--></a>')
   eq('< c1 x="y">{a:(j)<c2>}a', x)

   x = xlSAX('<?xml version="1.0"?><a></a>')
   eq('{?xml version="1.0"}{a:}a', x)

   x = xlSAX('<a />')
   eq('{a:}a', x)
end


function qt.tests.DOM()
   local x

   -- DOM tests
   local function xlDOM(str, map)
      return xl( xml.DOM(str, map) )
   end

   eq({{"A",_type="a"}}, xml.DOM('<a>A</a>'))

   x = xlDOM("<a>A</a>")
   eq("{:{a:(A)}}", x)

   x = xlDOM("<a><b x='1'>bb<c>cc</c>bb</b>aa<d>dd</dd></a>00<e>ee</ee>")
   eq("{:{a:{b;x=(1):(bb){c:(cc)}(bb)}(aa){d:(dd)}}(00){e:(ee)}}", x)

   x = xlDOM("<a><b x='1'>bb<c>cc</c>bb</b>aa<d>dd</dd></a>00<e>ee</ee>",
	     { a = xml.ByName{ b = xml.ByName{}}})
   eq("{;a={a;b={b;x=(1):}:}:}", x)

   x = xlDOM("<a><b x='1'>bb<c>cc</c>bb</b>aa<d>dd</dd></a>00<e>ee</ee>",
	     { a = xml.ByName{ b = xml.ByName(xml.CaptureText())}})
   eq("{;a={a;b={b;x=(1):(bb)(bb)}:}:}", x)

   x = xlDOM("<a><b x='1'>bb<c>cc</c>bb</b>aa<d>dd</dd></a>00<e>ee</ee>",
	     { a = xml.CaptureAll()})
   eq("{:{a:{b;x=(1):(bb){c:(cc)}(bb)}(aa){d:(dd)}}}", x)

   eq(nil, (xml.DOM("<a b=c></a>")))

   -- TextNode: unboxed text

   eq("{:(ABC)}",   xlDOM('<a> ABC </a>',      {a = xml.TextNode()}))
   eq("{:( ABC )}", xlDOM('<a> ABC </a>',      {a = xml.TextNode(true)}))
   eq("{:(BC )}",   xlDOM('<a> ABC </a>',      {a = xml.TextNode("B.*")}))
   eq("{:(AC)}",    xlDOM('<a>A<b>B</b>C</a>', {a = xml.TextNode()}) )
   eq("{:(A,BC)}",  xlDOM('<a>A<b/> BC </a>',  {a = xml.TextNode(nil,",")}))

   -- ByName

   x = xlDOM("<a>BBB</a>",  {a = xml.ByName(xml.TextNode())} )
   eq("{;a=(BBB):}", x)

   -- ListByName
   eq( {a={'1','2','3'}},
            xml.DOM( "<a>1</a><a>2</a><a>3</a>",
                     {a = xml.ListByName( xml.TextNode() )} ))


   -- default types

   eq( {a=1,b="ac"},
       xml.DOM( "<a>1</a><b>a<c>b</c>c</b>",
                {a = xml.NUMBER, b = xml.STRING} ) )

   eq( {a={1,2,3}, b={"4","5","6"}},
       xml.DOM( "<a>1</a><b>4</b><a>2</a><b>5</b><a>3</a><b>6</b>",
                { a = xml.NUMBER_LIST, b = xml.STRING_LIST } ))

   -- entities in DOM text

   x = xlDOM("<a x='&amp;'>A&amp;B</a>")
   eq("{:{a;x=(&):(A&B)}}", x)

   x = xlDOM("<a x='&amp;'>A&amp;B<![CDATA[a&amp;b]]></a>")
   eq("{:{a;x=(&):(A&B)(a&amp;b)}}", x)

   -- comments and processing instructions

   x = xlDOM("<!-- This is a comment -->")
   eq("{:{_comment:( This is a comment )}}", x)

   x = xlDOM("<?zip zap?>")
   eq("{:{_pi_zip:(zap)}}", x)
end


function qt.tests.stream()
   local function newRdr(txt, incr)
      local pos = 1
      local function read()
         local p = pos
         pos = pos + incr
         if pos > #txt then
            pos = #txt + 1
         end
         if p >= pos then
            return nil
         end
         return txt:sub(p,pos-1)
      end
      return read
   end

   local str = 'p<a x="" y = "Y>W">a1<b>bt</b> a3 <c/><d >D</d></a>post'
   for _, n in ipairs{ 55, 52, 51, 50, 4, 3, 2, 1} do
      local x = xlSAX( newRdr(str, n) )
      eq("(p){a;x=();y=(Y>W):(a1){b:(bt)}b( a3 ){c:}c{d:(D)}d}a(post)@n="..n,
         x.. "@n=" .. n)

      x = xlSAX( newRdr('<!-- C > B < D -->', n) )
      eq("< C > B < D >@n=" .. n,
         x .. "@n=" .. n)

      x = xlSAX( newRdr('<?foo C > B < D ?>', n) )
      eq("{?foo C > B < D }@n=" .. n,
         x .. "@n=" .. n)
   end
end


if arg[1] == "-dump" then
   local fname = arg[2]

   local cntElem = 0
   local cntData = 0
   local f = io.open(arg[1], "r")
   local text = f:read("*a")
   f:close()

   xml.SAX(text,
          function (text, n1, n2) cntData = cntData + n2 - n1 end,
          function (elem) cntElem = cntElem + 1 end)

   print("cntElem = " .. cntElem .. ", cntData = " .. cntData)
   return 1
else
   return qt.runTests()
end
