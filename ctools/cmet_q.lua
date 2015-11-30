-- Usage:  lua cmet_q.lua [cmet_exe]
-- Set cmet_q_v=1 for verbose output.
--
local qt = require "qtest"
local TE = require "testexe"

local tmpdir = assert(os.getenv("OUTDIR"))
local e = TE:new(arg[1] or "@cmet.lua", os.getenv("cmet_q_v"))

----------------------------------------------------------------
-- cmet tests
----------------------------------------------------------------

e "test/a.csv test/b.csv"
e:diff("test/cmet1.result")

e "test/a.csv test/b.csv -sort -iPLOC:10"
e:diff("test/cmet2.result")

local tf = tmpdir .. "/cmet3.tmp"
e( "test/a.csv test/b.csv -o "..tf )
e.diff( e.readFile("test/cmet3.result"), e.readFile(tf) )

-- output version
e( "-v" )
e:expect("^cmet 1.%d.-@")


-- .cmet with bad / missing fez files

local fezFile = [[
asdfasdfasdfasdfasdfasdf
]]

local cmetFile = [[
#csv group,file,bytes,fez
a,src/AEEBase.c,713,this-does-not-exist.fez
a,src/AEEFoo.c,1024,bad.fez
]]

local tf = tmpdir .. "/cmet_badfez.tmp"
e.writeFile(tf, cmetFile)
e.writeFile(tmpdir .. "/bad.fez", fezFile)
e( tf.. " -f bytes,name" )
e:expect("713 AEEBase.c")
e:expect("1024 AEEFoo.c")

print "cmet ok"
