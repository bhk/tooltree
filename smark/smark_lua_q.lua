local qt = require "qtest"
local luaMacro = require "smark_lua"
local testsource = require "testsource"


-- Test warning location fixup

local parentSource = testsource.new("l1\n    {}\n")
local source = parentSource:extract(2, {{8,10}})
local doc = {}
local x = luaMacro( { text = source.data, _source = source}, doc)
testsource.dmatch(
   parentSource.errors,
   {{".lua macro compilation\nTEST:2:5: unexpected symbol.*\n",8}}
)


-- Test free variables

local src = testsource.new [[
  return source.x .. doc.y
]]
src.x = "foo"
doc.y = "bar"

qt.eq("foobar", luaMacro( { text = src.data, _source = src}, doc ))
