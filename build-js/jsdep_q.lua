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

-- "--format"

e:exec("--path=" .. outdir
          .. " --format='A%sB'"
          .. " -o " .. outfile
          .. " " .. srcfile)
local out = e.readFile(outfile)
qt.match(out, "A.*/a.js .*/b.js .*/c.js\nB")


-- "--bundle" and "--odep"

e:exec("--bundle"
          .. " --path=" .. outdir
          .. " -o " .. outfile
          .. " --odep=" .. depfile
          .. " " .. srcfile)
out = e.readFile(outfile)
qt.match(out, "'%(main%)': ?function.-'b.js': ?function.-'c.js': ?function")

out = e.readFile(depfile)
qt.match(out, outfile .. ": .*a%.js .*b%.js .*c%.js")


-- "--html"

e:exec("--html"
          .. " --path=" .. outdir
          .. " -o " .. outfile
          .. " " .. srcfile)
out = e.readFile(outfile)
qt.match(out, "<title>A</title>")
qt.match(out, "<html>.-<script.->.-b%.js.-</script>")
