# Build (and run) a demo web server.

default = LuaExe(demo.lua)
run = LuaRun(demo.lua)
runExe = Run(LuaExe(demo.lua))

# lpeg is an indirect dependency
LuaEnv.luaPathDirs = . $(package.luau) $(package.monoglot) $(package.lpeg)

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk
