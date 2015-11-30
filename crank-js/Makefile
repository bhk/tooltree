include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

LuaEnv.luaPathDirs = . $(luau) $(lpeg)

LuaTest += $(wildcard *_q.lua)

LuaExe += jsdep.lua

ship.parent = Copy
ship += crank-js.min $(call get*,out,LuaExe)

$(build)
