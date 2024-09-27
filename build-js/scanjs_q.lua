local scanjs = require "scanjs"
local lpeg = require "lpeg"
local qt = require "qtest"

local eq = qt.eq
local C, P = lpeg.C, lpeg.P

local function remainder(pat, subject)
   return (pat * C(P(1)^0)):match(subject)
end


-- optional whitespace

eq(remainder(scanjs.ws, " /* * / */abc"), "abc")
eq(remainder(scanjs.ws, " //abc\r\nnext line"), "next line")

-- match function call

eq({scanjs.funCall:match("abcd ( 'module' );")},
   {"abcd", "module"})


-- find all `require` calls with literal strings

local source1 = [[
// title: Name
/* comment
*/ require // comment
( /* comment */
 "abc") // comment

foo.require("xyz"); // not scanned

require('def')require("ghi")]]

local o = scanjs.scan(source1)
eq(o.requires, { "abc", "def", "ghi" })
eq(o.title, "Name")
