# Build the XPIO native extension and test Lua modules.
# Deploys libraries and sources to .out/$V/exports/...

Alias(default).in = CTest@*_q.c LuaTest@*_q.lua Ship(exports)

exports = @libs @luaSources
libs = LuaSharedLib(xpio_c.c) LuaLib(xpio_c.c)
luaSources = $(filter-out %_q.lua,$(wildcard *.lua))

LuaEnv.luaPathDirs = . $(package.luau) $(package.lpeg)
LuaEnv.luaCPathLibs = $(libs)

# test C extensions before testing Lua files
LuaTest.deps = {inherit} CTest@*_q.c

# xpio_c_q.c depends on Lua headers and library functions (CExe inferred from CTest)
CExe(xpio_c_q.c).inferClasses = LuaCC.c
CExe(xpio_c_q.c).in = {inherit} $(package.lua)/lib/liblua.lib
CExe(xpio_c_q.c).libFlags = {inherit} -lm

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk
