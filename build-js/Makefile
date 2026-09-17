# Build & deploy jsdep (as an executable) and build-js.mk

default = LuaTest@*_q.lua Ship(exports)
exports = LuaExe(jsdep.lua) build-js.mk build-js.txt

LuaEnv.exports = {inherit} OUTDIR
LuaEnv.OUTDIR = $(VOUTDIR)
LuaEnv.luaPathDirs = . $(package.luau) $(package.lpeg)

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk

