Alias(default).in = Perf(web.lua) Perf(web.js)

LuaEnv.luaPathDirs = . $(luau-exports) $(monoglot-exports) $(lpeg-exports)

Perf.inherit = LuaRun
Perf.exec = {exportPrefix} ./time.sh {webserver}
Perf.webserver = {luaExe} {<}
Perf(web.js).webserver = node {<}

include-deps = $(build-lua-exports)/build-lua.mk
include ../build/tooltree.mk

