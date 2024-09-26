# This builds an executable for Smark and deploys it along with
# documentation, and related make include files to .out/$V/exports/...

Alias(default).in = Ship(exports) LuaTest@luaTests
exports = LuaExe(smark.lua) smark.txt smark.mk SmarkDoc(smark.txt)
luaTests = $(wildcard *_q.lua)

# ugh: smark_q.lua uses chdir, so we have to use absolute paths for LUA_PATH
LuaEnv.luaPathDirs = $(abspath . $(luau-exports)/src $(lpeg-exports))
LuaEnv.luaCPathDirs = $(luau-exports)/lib $(lpeg-exports)

LuaTest.exports = {inherit} OUTDIR
LuaTest.OUTDIR = $(VOUTDIR)

SmarkDoc.up = LuaExe(smark.lua)
SmarkDoc.exe = $(firstword {up^})


# Test ordering
html2d_q.lua = 
markup_q.lua = html2d smarkmisc source
mscgen_q.lua = html2d
smark_art_q.lua = smarkmisc
smark_include_q.lua = html2d markup smarkmisc source
smark_lua_q.lua = html2d markup smarkmisc source
smark_msc_q.lua = html2d markup mscgen smarkmisc source
smark_q.lua = 
smark_table_q.lua = html2d markup smarkmisc source
smarkmisc_q.lua = 
source_q.lua = smarkmisc

LuaTest.deps = $(patsubst %,LuaTest(%_q.lua),$({<}))


include smark.mk
include ../build-lua/build-lua.mk
include ../minion/tooltree.mk
