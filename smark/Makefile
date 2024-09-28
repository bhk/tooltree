# This builds an executable for Smark and deploys it along with
# documentation, and related make include files to .out/$V/exports/...

Alias(default).in = Ship(exports) LuaTest@luaTests

exports = LuaExe(smark.lua) smark.txt smark.mk SmarkDoc(smark.txt)
luaTests = $(wildcard *_q.lua)

# ugh: smark_q.lua uses chdir, so we have to use absolute paths for LUA_PATH
LuaEnv.luaPathDirs = $(abspath . $(luau-exports) $(lpeg-exports))

LuaTest.exports = {inherit} OUTDIR
LuaTest.OUTDIR = $(VOUTDIR)

SmarkDoc.up = LuaExe(smark.lua)
SmarkDoc.exe = $(firstword {up^})

include smark.mk
include ../build-lua/build-lua.mk
include ../build/tooltree.mk
