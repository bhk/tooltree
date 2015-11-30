local Html2D = require "html2d"
local qt = require "qtest"

require "mscgen" -- test compilation & treat as dependency
local msc = qt.load "mscgen.lua"

local parse, render = msc.parse, msc.render
local eq = qt.eq


local events = {}
local function eventLogger(...)
   table.insert(events, {...})
end

local m, pos

local function parseText(input)
   events = {}
   m, pos = parse(input, eventLogger)
   if #events > 0 then
      qt.printf("Error events: %Q\n", events)
   end
   qt._eq(0, #events, 2)
   qt._eq("table", type(m), 2)
   return m, pos
end

--------------------------------
local _gc = {}
function _gc:__index(name)
   self[name] = function (...) table.insert(self.log, {name=name, ...}) end
   return self[name]
end
local function newGC()
   return setmetatable({log={}}, _gc)
end

----------------------------------------------------------------
-- simple parsing tests
----------------------------------------------------------------

parseText [[
msc {
  a [ arclinecolour = "blue"],b,c;
  a -> b, b =>c;
  c <= a [arclinecolor = "red"];
}
]]

eq("a", m.entities[1].key)
eq("b", m.entities[2].key)
eq("c", m.entities[3].key)

eq(2, #m.arcs[1])
eq({lpos=44, lhs="a", op="->", rpos=49, rhs="b", attrs={}}, m.arcs[1][1])
--eq({"b", "=>", "c"}, m.arcs[1][2].arc)
--eq({"c", "<=", "a"}, m.arcs[2][1].arc)

eq( {{key="arclinecolour", value="blue"}}, m.entities[1].attrs)
eq( {{key="arclinecolor", value="red"}}, m.arcs[2][1].attrs)


-- No "msc"

parseText [[
{
  a [ arclinecolour = "blue"],b,c;
  a -> b, b =>c;
  c <= a [arclinecolor = "red"];
}
]]



-- No "msc {" and "}"

parseText [[
  a [ arclinecolour = "blue"],b,c;
  a -> b, b =>c;
  c <= a [arclinecolor = "red"];
]]


-- ## Comments

parseText [[
  # This is a bash-style comment
  a [ arclinecolour = "blue"],b,c;
  // This is a C++-style comment
  a -> b, b =>c;
  /* This is a C-style comment */
  c <= a [arclinecolor = "red"];
]]


-- ## Special characters in strings may be escaped with `\`

parseText [[ a [ label = "_\"_\'_\\_"]; ]]

eq([[_"_'_\_]], m.entities[1].attrs[1].value)


----------------------------------------------------------------
-- error cases
----------------------------------------------------------------
--
-- Try to report errors with positions in the string that would
-- be useful to the user.

local errPat = ""

local function parseError(str, bRender)
   events = {}
   local m = parse(str, eventLogger)
   if bRender then
      render(m, newGC())
   end
   eq(1, #events)
   qt.match(table.concat(events[1], ",", 2), errPat)
end

-- ## Invalid character after an ID... could be invalid option, or entity,
--     or arc.

errPat = "expected.*%["
parseError"  a ] ;"

-- ## Bug: fail on this invalid fragment.

errPat = "e"
parseError '  a rbx b [ label = "box" ]; '


-- ## Rendering error

local function renderError(str)  parseError(str, true) end

errPat = "unsupported"
renderError ' wwidth="300"; a,b; '

errPat = "appears"
renderError ' width="300", width="300"; a,b; '

errPat = "left.*or.*right"
renderError ' float = "xxx"; a,b; '

errPat = "numeric"
renderError ' width="abc"; a,b; '

----------------------------------------------------------------
-- More complex examples
----------------------------------------------------------------

parseText [[
# MSC for some fictional process
msc {
   a, b;
   |||;
   a rbox b [ label = "box" ];
   |||;
   a box a [ label = "just a" ],
   b abox b [ label = "just b" ];
   |||;
}
]]


parseText [[
# MSC for some fictional process
msc {
   hscale = "0.75";

   a [ linecolor = "#990"],
   b [ arclinecolor="#00b", arctextcolor="#0aa"] ,
   c [ linecolor="#0a0"];

   b -> c [ label = "func(TRUE)" ] ;
   a :> c [ label = "call(1)" ];
   c=>c [ label = "work" ];
   c=>c [ label = "more work", textcolor="#d00" ];
   ...;
   c=>c [ label = "yet more" ];
   a -> b [ label = "ab()", linecolour = "#d00"];
   a<<=c [ label = "callback()"];
   ---  [ label = "Horizontal Line", ID="*", linecolor="#d00" , textcolor="#080"];
   a->a [ label = "next()"];
   a->c [ label = "first line\nsecond"];
   b<-c [ label = "right-to-left"];
   b->b [ label = "middle"];
   a<-b [ label = "RTL"];

   |||;  a box c [ label = "ordinary box" ];
   |||;  a rbox b [ label = "rounded" ],    c rbox c [ label = "same line" ];
   |||;
}
]]

local filename = os.getenv("MSCGEN_OUT") or ""
if filename ~= "" then
   local gc = Html2D:new()
   render(m, gc)
   local html = gc:genHTML("font: 11px Verdana");
   local f = io.open(filename, "wb")
   f:write(html)
   f:close()
   print("msc: wrote file: " .. filename)
end

