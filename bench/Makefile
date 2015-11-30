include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

LuaEnv.luaPathDirs = . $(luau) $(monoglot) $(lpeg)

# LuaExe += web.lua

Perf += web.lua web.js

# Type 'make Perf' to run benchmarks.  `httperf` is expected to be in PATH.
#
Perf.prereqOf =
Perf.parent = LuaEnv Gen
Perf.exe = ./time.sh
Perf.Quiet = @@
Perf.exports = $(call inherit) webserver
Perf.webserver = $(call .,luaExe) $I
Perf.command = $(call .,exe)

Perf[web.js].webserver = node $I

$(build)
