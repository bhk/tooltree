# Test Lua sources and build the XPFS Lua extension (static & dynamic).
# Libraries and sources are deployed to .out/$V/exports/{bin,src}

lua-exports ?= ../lua/$(VOUTDIR)exports

Alias(default).in = Ship(exports/bin,exports/src) LuaTest@luaTests
exports/bin = SharedLib(xpfs.c) Lib(xpfs.c)
exports/src = $(filter-out %_q.lua build.lua,$(wildcard *.lua))
luaTests = $(wildcard *_q.lua)

CC.includes = $(lua-exports)/src

LuaTest.OUTDIR = {outDir}
LuaTest.LUA = {exe}
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

# ../minion/scanluatests.scm generates this dependency map.  It ensures that
# tests will be re-run after their dependencies change, and also that each
# test will NOT be run before its dependencies have been tested (to avoid
# chasing red herrings in debugging).
cmap = memoize qtest
csv = qtest
doctree = memoize qtest
errors = qtest
fsu = qtest
futils = fsu lfsu qtest xpfs
getopts = qtest
htmlgen = doctree memoize object opairs qtest utf8utils
json = qtest serialize utf8utils
lfsu = fsu qtest xpfs
list = object serialize
memoize = qtest
minify = qtest
object = qtest
opairs = qtest
qtest = 
redir = qtest
requirefile = qtest
serialize = qtest
testexe = list object qtest redir serialize xpexec
tree = fsu lfsu qtest xpfs
utf8utils = qtest
xml = qtest utf8utils
xpexec = list object qtest serialize
xpfs = qtest
xuri = qtest

LuaTest.modname = $(patsubst %_q.lua,%,{<})
LuaTest.deps = $(patsubst %,LuaTest(%_q.lua),$({modname}))

include ../minion/tooltree.mk
