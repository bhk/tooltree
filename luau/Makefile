# Test Lua sources and build the XPFS Lua extension (static & dynamic).
# Libraries and sources are deployed to .out/$V/exports/{lib,src}

Alias(default).in = Ship(exports) LuaTest@*_q.lua

exports = @libs $(filter-out %_q.lua,$(wildcard *.lua))
libs = LuaSharedLib(xpfs.c) LuaLib(xpfs.c)

# Export these environment variables used by tests
LuaTest.OUTDIR = {outDir}
LuaTest.LUA = {luaExe}
LuaTest.exports = {inherit} OUTDIR
LuaTest(xpexec_q.lua).exports = {inherit} LUA 
LuaTest(testexe_q.lua).exports = {inherit} LUA

# Some tests depend on xpfs.so; might as well make all of them dependent.
LuaTest.luaCPathLibs = $(libs)

# requirefile_q reads results json_q.lua's OK file
LuaTest(requirefile_q.lua).exports = {inherit} REQUIREFILE_PATH
LuaTest(requirefile_q.lua).REQUIREFILE_PATH = .;{outDir}
LuaTest(requirefile_q.lua).deps = {inherit} LuaTest(json_q.lua)

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk
