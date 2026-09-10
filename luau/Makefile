# Test Lua sources and build the XPFS Lua extension (static & dynamic).
# Libraries and sources are deployed to .out/$V/exports/{lib,src}

default = Ship(exports) LuaTest@*_q.lua

exports = @libs $(filter-out %_q.lua,$(call _wildcard,*.lua))
libs = LuaSharedLib(xpfs.c) LuaLib(xpfs.c)

# Export these environment variables used by tests
LuaTest.OUTDIR = {outDir}
LuaTest.LUA = {luaExe}
LuaTest.exports = {inherit} OUTDIR
LuaTest(xpexec_q.lua).exports = {inherit} LUA 
LuaTest(testexe_q.lua).exports = {inherit} LUA

# Some tests depend on xpfs.so; might as well make all of them dependent.
LuaTest.luaCPathLibs = $(libs)

# requirefile_q reads results from {dataFile}
LuaTest(requirefile_q.lua).in = {inherit} {dataFile}
LuaTest(requirefile_q.lua).dataFile = Write(data:DATA)
LuaTest(requirefile_q.lua).execArgs = $(notdir {{dataFile}.out})
LuaTest(requirefile_q.lua).REQUIREFILE_PATH = .;$(dir {{dataFile}.out})
LuaTest(requirefile_q.lua).exports = {inherit} REQUIREFILE_PATH

include ../build/tooltree.mk
