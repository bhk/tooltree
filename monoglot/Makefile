# Build the XPIO native extension and test Lua modules.
# Deploys libraries and sources to .out/$V/exports/...

Alias(default).in = CTest@cTests LuaTest@luaTests Ship(exports) 
exports = @libs @luaSources
libs = LuaSharedLib(xpio_c.c) LuaLib(xpio_c.c)

luaSources = $(filter-out %_q.lua,$(wildcard *.lua))
luaTests = $(filter %_q.lua,$(wildcard *.lua))
cTests = $(wildcard *_q.c)

LuaEnv.luaPathDirs = . $(luau-exports) $(lpeg-exports)
LuaEnv.luaCPathLibs = $(libs)

# xpio_c_q.c depends on Lua headers and library functions (Exe inferred from CTest)
Exe(xpio_c_q.c).inferClasses = LuaCC.c
Exe(xpio_c_q.c).in = {inherit} $(lua-exports)/lib/liblua.lib
Exe(xpio_c_q.c).libFlags = {inherit} -lm

# Run unit tests in order
bufio_q.lua = 
dino_q.lua = 
event_q.lua = heap queue thread xpio_c xpio
futex_q.lua = event heap queue thread xpio_c xpio
heap_q.lua = 
httpd_q.lua = bufio heap queue substream thread xpio_c xpio
popen_q.lua = bufio heap queue thread xpio_c xpio
queue_q.lua = 
substream_q.lua = 
thread_q.lua = heap queue xpio_c xpio
xpio_c_q.lua = 
xpio_q.lua = xpio_c

LuaTest.deps = {inherit} $(patsubst %,LuaTest(%_q.lua),$({<})) CTest@cTests

include ../build-lua/build-lua.mk
include ../build/tooltree.mk
