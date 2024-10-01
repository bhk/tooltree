# Build the XPIO native extension and test Lua modules.
# Deploys libraries and sources to .out/$V/exports/...

Alias(default).in = CTest@cTests LuaTest@luaTests Ship(exports)

exports = @libs @luaSources
libs = LuaSharedLib(xpio_c.c) LuaLib(xpio_c.c)
luaSources = $(filter-out %_q.lua,$(wildcard *.lua))
luaTests = $(filter %_q.lua,$(wildcard *.lua))
cTests = $(wildcard *_q.c)

LuaEnv.luaPathDirs = . $(package.luau) $(package.lpeg)
LuaEnv.luaCPathLibs = $(libs)

# test C extensions before testing Lua files
LuaTest.deps = {inherit} CTest@cTests

# xpio_c_q.c depends on Lua headers and library functions (Exe inferred from CTest)
Exe(xpio_c_q.c).inferClasses = LuaCC.c
Exe(xpio_c_q.c).in = {inherit} $(package.lua)/lib/liblua.lib
Exe(xpio_c_q.c).libFlags = {inherit} -lm

include-imports = build-lua/build-lua.mk
include ../build/tooltree.mk
