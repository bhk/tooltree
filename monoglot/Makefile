# External dependencies
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

# this is used by LuaExe & LuaTest
LuaEnv.luaPathDirs = . $(luau) $(lpeg)

# Run Lua unit tests

LuaTest += $(wildcard *_q.lua)

LuaTest[xpio_c_q.lua].deps = $(call inherit) xpio_c.c

# Run C unit tests

# TODO: LuaExeTest += xpio_q.c
ExeTest += $(wildcard *_q.c)
Exe[xpio_c_q.c].in = $I $(lua)/lib/liblua.lib
Exe[xpio_c_q.c].flags = $(call inherit) lm
Compile.includes = $(lua)/src


# Make unit tests run in a precise order (debug lower-level ones first)
testOrder = bufio xpio_c xpio thread substream httpd event
orderDeps = $(if $1,$(if $2,$(\n)LuaTest[$(word 1,$1)].ooDeps = $$(call inherit) $2) \
    $(call orderDeps,$(wordlist 2,999,$1),$(call get,out,LuaTest,$(word 1,$1)) $2))
$(call <eval>,$(foreach v,$V,$(call orderDeps,$(testOrder:%=%_q.lua))))

# Ship xpio library and related lua modules
LuaExt += xpio_c.c

Ship.parent = Copy
Ship.dir = out/$v
Ship = $(call get*,out,LuaExt) $(filter-out %_q.lua build.lua,$(wildcard *.lua))

$(build)
