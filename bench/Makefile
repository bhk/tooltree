Alias(default).in = Perf(web.lua) Perf(web.js)

LuaEnv.luaPathDirs = . $(package.luau) $(package.monoglot) $(package.lpeg)

Perf.inherit = LuaRun
Perf.exec = {exportPrefix} ./time.sh {webserver}
Perf.webserver = {luaExe} {<}
Perf(web.js).webserver = node {<}

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk

