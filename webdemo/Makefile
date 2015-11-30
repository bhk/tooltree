# External dependencies
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

# To run `lua demo.lua`:    make LuaRun=demo
# To run the demo binary:   make open=demo

# lpeg is an indirect dependency
LuaEnv.luaPathDirs = . $(luau) $(monoglot) $(lpeg)

# Build demo from demo.lua
LuaExe += demo.lua

$(build)
