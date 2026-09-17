# Build & deploy jsdep (as an executable) and build-js.mk

default = LuaTest@*_q.lua Ship(exports)
exports = LuaExe(jsdep.lua) build-js.mk build-js.txt

LuaEnv.exports = {inherit} OUTDIR
LuaEnv.OUTDIR = $(VOUTDIR)

include ../build/tooltree.mk

