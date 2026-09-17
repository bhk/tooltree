default = LuaPerf(web.lua) JSPerf(web.js)

LuaPerf.inherit = LuaRun
LuaPerf.exec = port=8002 ./time.sh {luaExe} {<}
LuaPerf.luaPathDirs = . $(package.luau) $(package.monoglot) $(package.lpeg)

JSPerf.inherit = Run
JSPerf.exec = port=8001 ./time.sh node {<}

includeImports = build-lua/build-lua.mk
MAKEFLAGS = -R -j1 # don't run in parallel; see tooltree.mk
include ../build/tooltree.mk
