# Build (and run) a demo web server.

Alias(default).in = LuaExe(demo.lua)
Alias(run).in = LuaRun(demo.lua)
Alias(runExe).in = Run(LuaExe(demo.lua))

# lpeg is an indirect dependency
LuaEnv.luaPathDirs = . $(package.luau) $(package.monoglot) $(package.lpeg)

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk
