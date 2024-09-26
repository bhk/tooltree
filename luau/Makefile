# Test Lua sources and build the XPFS Lua extension (static & dynamic).
# Libraries and sources are deployed to .out/$V/exports/{lib,src}

Alias(default).in = Ship(exports) LuaTest@luaTests
exports = SharedLib(xpfs.c) Lib(xpfs.c) $(filter-out %_q.lua,$(wildcard *.lua))
luaTests = $(wildcard *_q.lua)

CC.includes = $(lua-exports)/src

LuaTest.OUTDIR = {outDir}
LuaTest.LUA = {luaExe}
LuaTest.LUA_FLAGS =
LuaTest.exports = {inherit} OUTDIR
LuaTest(xpexec_q.lua).exports = {inherit} LUA LUA_FLAGS
LuaTest(testexe_q.lua).exports = {inherit} LUA LUA_FLAGS

# These tests depend on xpfs.so
xpfs_dir = $(dir $(call get,out,SharedLib(xpfs.c)))
LuaTest(xpfs_q.lua).luaCPathDirs = $(xpfs_dir)
LuaTest(xpfs_q.lua).deps = {inherit} SharedLib(xpfs.c)
LuaTest(lfsu_q.lua).luaCPathDirs = $(xpfs_dir)
LuaTest(lfsu_q.lua).deps = {inherit} SharedLib(xpfs.c)
LuaTest(futils_q.lua).luaCPathDirs = $(xpfs_dir)
LuaTest(futils_q.lua).deps = {inherit} SharedLib(xpfs.c)

# requirefile_q reads results json_q.lua's OK file
LuaTest(requirefile_q.lua).exports = {inherit} REQUIREFILE_PATH
LuaTest(requirefile_q.lua).REQUIREFILE_PATH = .;{outDir}
LuaTest(requirefile_q.lua).deps = {inherit} LuaTest(json_q.lua)

# ../build/scanluatests.scm generates this dependency map.  It ensures that
# tests will be re-run after their dependencies change, and also that each
# test will NOT be run before its dependencies have been tested (to avoid
# chasing red herrings in debugging).
cmap_q.lua = memoize qtest
csv_q.lua = qtest
doctree_q.lua = memoize qtest
errors_q.lua = qtest
fsu_q.lua = qtest
futils_q.lua = fsu lfsu qtest xpfs
getopts_q.lua = qtest
htmlgen_q.lua = doctree memoize object opairs qtest utf8utils
json_q.lua = qtest serialize utf8utils
lfsu_q.lua = fsu qtest xpfs
list_q.lua = object serialize
memoize_q.lua = qtest
minify_q.lua = qtest
object_q.lua = qtest
opairs_q.lua = qtest
qtest_q.lua = 
redir_q.lua = qtest
requirefile_q.lua = qtest
serialize_q.lua = qtest
testexe_q.lua = list object qtest redir serialize xpexec
tree_q.lua = fsu lfsu qtest xpfs
utf8utils_q.lua = qtest
xml_q.lua = qtest utf8utils
xpexec_q.lua = list object qtest serialize
xpfs_q.lua = qtest
xuri_q.lua = qtest

LuaTest.deps = $(patsubst %,LuaTest(%_q.lua),$({<}))

include ../build-lua/build-lua.mk
include ../build/tooltree.mk
