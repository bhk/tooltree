-- Test jsdep
--
-- For debug output, set env variable "jsdep_q_v".
--

local qt = require "qtest"
local TE = require "testexe"

local e = TE:new("@jsdep.lua", os.getenv("jsdep_q_v"))

local outdir = assert(os.getenv("OUTDIR"), "OUTDIR variable not set")

local sources = {
   a = '// title: A\nrequire("b.js");\nrequire("c.js");',
   b = 'require("c.js");',
   c = '//'
}

for name, text in pairs(sources) do
   e.writeFile(outdir .. name .. ".js", text)
end

local srcfile = outdir .. "a.js"
local outfile = outdir .. "jsdep_q.tmp"
local depfile = outdir .. "a.js.d"

-- generate deps

e:exec("--path=" .. outdir
          .. " -o " .. outfile
          .. " " .. srcfile)
local out = e.readFile(outfile)
qt.match(out, ".*/a.js .*/b.js .*/c.js")

-- "--bundle" and "-MF"

e:exec("--bundle"
          .. " --path=" .. outdir
          .. " -o " .. outfile
          .. " -MF " .. depfile
          .. " " .. srcfile)
out = e.readFile(outfile)
qt.match(out, "'%(main%)': ?function.-'b.js': ?function.-'c.js': ?function")

out = e.readFile(depfile)
--
qt.match(out, outfile .. ": .*a%.js .*b%.js .*c%.js")
-- Assert: phony rule present
qt.match(out, "\n" .. outdir .. "a.js:\n")


-- "-MT" & "-Moo"

e:exec("--bundle"
          .. " --path=" .. outdir
          .. " -o " .. outfile
          .. " -MF " .. depfile
          .. " -MT " .. outdir .. "a_q.js"
          .. " -Moo ^B_q^S"
          .. " " .. srcfile)
out = e.readFile(outfile)
qt.match(out, "'%(main%)': ?function.-'b.js': ?function.-'c.js': ?function")

out = e.readFile(depfile)
-- Assert: -MT overrides -o as target
-- Assert: order-only dependency present
-- Assert: dependency matching target is omitted
-- Assert: phony rules present for OO deps
qt.match(out, ".*a_q%.js ?: .*a.js .*b.js .* | .*b_q.js .*c.js")
qt.match(out, "\n" .. outdir .. "b_q.js:\n")


-- "--html"

e:exec("--html"
          .. " --path=" .. outdir
          .. " -o " .. outfile
          .. " " .. srcfile)
out = e.readFile(outfile)
qt.match(out, "<title>A</title>")
qt.match(out, "<html>.-<script.->.-b%.js.-</script>")
