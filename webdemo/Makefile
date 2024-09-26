# Build (and run) a demo web server.

Alias(default).in = LuaExe(demo.lua)
Alias(run).in = LuaRun(demo.lua)
Alias(runExe).in = Run(LuaExe(demo.lua))

# lpeg is an indirect dependency
LuaEnv.luaPathDirs = . $(luau-exports)/src $(monoglot-exports) $(lpeg-exports)
LuaEnv.luaCPathDirs = $(luau-exports)/lib $(monoglot-exports) $(lpeg-exports)

include ../build-lua/build-lua.mk
include ../build/tooltree.mk
