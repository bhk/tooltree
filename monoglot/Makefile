# Build the XPIO native extension and test Lua modules.
# Deploys libraries and sources to .out/$V/exports/...

Alias(default).in = CTest@cTests LuaTest@luaTests Ship(exports) 
exports = SharedLib(xpio_c.c) Lib(xpio_c.c) @luaSources

luaSources = $(filter-out %_q.lua,$(wildcard *.lua))
luaTests = $(filter %_q.lua,$(wildcard *.lua))
cTests = $(wildcard *_q.c)

LuaEnv.luaPathDirs = . $(luau-exports)/src $(lpeg-exports)
LuaEnv.luaCPathDirs = $(luau-exports)/lib $(lpeg-exports) $(dir $(call get,out,SharedLib(xpio_c.c)))

# Compile & link Lua extensions
Compile.includes = $(lua-exports)/src
Exe.in = {inherit} $(lua-exports)/lib/liblua.lib
Exe.libFlags = {inherit} -lm

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

LuaTest.deps = $(patsubst %,LuaTest(%_q.lua),$({<}))

LuaTest(xpio_c_q.lua).deps = {inherit} CTest@cTests

include ../build-lua/build-lua.mk
include ../build/tooltree.mk
