default = LuaPerf(web.lua) JSPerf(web.js)

LuaPerf.inherit = LuaRun
LuaPerf.exec = port=8002 ./time.sh {luaExe} {<}

JSPerf.inherit = Run
JSPerf.exec = port=8001 ./time.sh node {<}

MAKEFLAGS = -R -j1 # don't run in parallel; see tooltree.mk
include ../build/tooltree.mk
