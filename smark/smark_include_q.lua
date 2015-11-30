local qt = require "qtest"
local markup = require "markup"
local includeMacro = require "smark_include"
local testsource = require "testsource"


local text = "abc\n.include:   smark_include_qs.lua  \n"
local parent = testsource.new(text)
local source = parent:extract(5, {{14,39}})

local succ, value = pcall(function ()
    return includeMacro.expand( {text = source.data, _source = source},
                                {parse = markup.parseDoc} )
end)

qt.eq(false, succ)
testsource.dmatch(parent.errors, {"Could not find file.*", 14})

