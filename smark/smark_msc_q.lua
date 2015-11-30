local qt = require "qtest"
local mu = require "markup"
local Source = require "source"
local testsource = require "testsource"

require "smark_msc" -- test compile & ensure cfromlua treats it as a dependency

-- Check error handling and location fixups

local text = [[
Line 1

.msc
      a, b, c;
      a -> b:
      b => c;

]]

local src = testsource.new(text)
local tree = mu.expandDoc( mu.parseDoc( src ) )
testsource.dmatch(src.errors, {"msc: expected.*",41})


-- Exercise functionality and verify something is generated

local text = [[
.msc
   # options
   hscale = "0.75";

   # entities (entity labels not standard?)
   a [ linecolor = "#990", label="client"],
   b [ arclinecolor="#00b", arctextcolor="#0aa", label="server 1"] ,
   c;

   # arcs
   b -> c [ label = "func(TRUE)" ] ;
   a :> c;
   c=>c;
   ... [ label = "...time passes...", idurl="#\\counter", id="2"];
   c=>c [ label = "more work", textcolor="#d00", url="#ASCII Graphics" ];
   c=>c [ label = "process(END)", textbgcolor="#ffd" ];
   a -> b [ label = "ab()", linecolour = "#d00"];

   a -> * [ label = "broadcast" ];

   ---  [ label = "Horizontal Line", ID="*", linecolor="#d00" , textcolor="#080"];
   a->a;  # to self
   a->c;  # span two
   b<-c;  # right to left
   b->b;  # to self in middle

   a -> c [ label = "arcskip=1", arcskip=1 ];
   a RBOX b [ label = " label=\"box\"\nlinecolor=\"blue\"\nthird line", url="#.msc" ];
   a rbox b [ label = "rounded" ],    c rbox c [ label = "same line" ];
   |||;

]]

local src = testsource.new(text)
local tree = mu.expandDoc( mu.parseDoc( src ) )
qt.eq({}, src.errors)
