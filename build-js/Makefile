# Build & deploy jsdep (as an executable) and build-js.mk

Alias(default).in = LuaTest@luaTests Ship(exports)
exports = LuaExe(jsdep.lua) build-js.mk build-js.txt
luaTests = $(wildcard *_q.lua)

LuaEnv.exports = {inherit} OUTDIR
LuaEnv.OUTDIR = $(VOUTDIR)
LuaEnv.luaPathDirs = . $(luau-exports) $(lpeg-exports) $(monoglot-exports)

include ../build-lua/build-lua.mk
include ../build/tooltree.mk

