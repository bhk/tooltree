-- Usage:  lua ccov_q.lua [ccov_exe]
--
-- Set ccov_q_v=1 for verbose output when debugging.
--

local qt = require "qtest"
local TE = require "testexe"

local tmpdir = assert(os.getenv("OUTDIR"))
local e = TE:new(arg[1] or "@ccov.lua", os.getenv("ccov_q_v"))
if e.bVerbose then
   e.bTee = true
   print("tmpdir = '" .. tmpdir .. "'")
end

-- Make sure we don't collide with other tests running in parallel
e.filePrefix = e.filePrefix .. "-ccov-"

----------------------------------------------------------------
-- ccov tests
----------------------------------------------------------------

local function trimTrailingSpaces(str)
   return ( str:gsub(" *\n", "\n") )
end

local function ccov(args)
   e.checkExit = true
   if args:sub(1,1) == "!" then
      e.checkExit = false
      args = args:sub(2)
   end
   return e(args)
end


ccov "-v"
e:expect("^ccov 1.%d.-@")

local tf = tmpdir .. "/ccov1.tmp"
ccov("test/c.xml test/d.csv -o " .. tf)
e.diffStrings( e.readFile("test/ccov_c_d.result"), e.readFile(tf) )

ccov "test/ccovtest.c.gcov.csv --list=test/ccovtest.c -o /dev/stdout"
e:diff "test/ccovtest.c-gcov.result"

ccov "test/ccovtest.c.bullseye.csv --list=test/ccovtest.c --style=be -o /dev/stdout"
e.out = trimTrailingSpaces(e.out)
e:diff "test/ccovtest.c-be.result"

ccov "test/ccovtest.c.gcov.csv -o /dev/stdout --raw"
e:diff "=#csv file,lct\ntest/ccovtest.c,::::0:0::::2:2::1:::::1:1:1:1::1::1:::1::0::0:::::1:::1::1:1:0:1:::1:1:1\n"

ccov "test/ccovtest.c.gcov.csv -o /dev/stdout --stats"
e:expect( "#csv file,linesExecutable,linesExecuted,pctExecuted\r?\n" ..
          "test/ccovtest.c,23,18,78.*")

ccov "!test/ccovtest.c.gcov.csv -o /dev/stdout --stats --raw"
assert( string.find(e.stderr, "contradicting"))

ccov "!test/ccovtest.c.gcov.csv --list=test/ccovtest.c --error -o /dev/stdout"
e.diffStrings(e.readFile("test/ccovtest.c-error.result"), e.stderr, 1)


-- test legacy options

ccov "test/ccovtest.c.bullseye.csv -be test/ccovtest.c"
e.out = trimTrailingSpaces(e.out)
e:diff "test/ccovtest.c-be.result"

ccov "test/ccovtest.c.gcov.csv -gcov test/ccovtest.c"
e:diff( "test/ccovtest.c-gcov.result" )


print "ccov ok"
