# This builds an executable for Smark and deploys it along with
# documentation, and related make include files to .out/$V/exports/...

Alias(default).in = Ship(exports) LuaTest@*_q.lua

exports = LuaExe(smark.lua) smark.txt hello.txt smark.mk SmarkDoc(smark.txt)

# ugh: smark_q.lua uses chdir, so we have to use absolute paths for LUA_PATH
LuaEnv.luaPathDirs = $(abspath . $(package.luau) $(package.lpeg))

LuaTest.exports = {inherit} OUTDIR
LuaTest.OUTDIR = $(VOUTDIR)

SmarkDoc.up = LuaExe(smark.lua)
SmarkDoc.smarkExe = $(firstword {up^})

include smark.mk
includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk
