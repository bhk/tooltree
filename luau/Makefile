# External dependencies
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min


LuaExt = xpfs.c


LuaTest = $(wildcard *_q.lua)
LuaTest.LUA = $(firstword $(or $(call v.,c-emulator),$(lua)/bin/lua))
LuaTest.LUA_FLAGS = $(if $(call v.,c-emulator),$(wordlist 2,99,$(call v.,c-emulator) $(lua)/bin/lua))
LuaTest[xpexec_q.lua].exports = $(inherit) LUA LUA_FLAGS
LuaTest[testexe_q.lua].exports = $(inherit) LUA LUA_FLAGS

LuaTest[requirefile_q.lua].exports = $(call inherit) REQUIREFILE_PATH
LuaTest[requirefile_q.lua].REQUIREFILE_PATH = .;$(call get,dir,LuaTest,json_q.lua)
LuaTest[requirefile_q.lua].deps = $(call inherit) $(call get,out,LuaTest,json_q.lua)


Ship.parent = Copy
Ship.dir = out/$v
Ship = $(call get*,out,LuaExt) $(filter-out %_q.lua build.lua,$(wildcard *.lua))


# order unit tests lower-to-higher
testOrder = qtest xpfs fsu lfsu futils tree
orderDeps = $(if $1,$(if $2,$(\n)LuaTest[$(word 1,$1)].deps += $2) \
    $(call orderDeps,$(wordlist 2,999,$1),$(call get,out,LuaTest,$(word 1,$1)) $2))
$(call <eval>,$(foreach v,$V,$(call orderDeps,$(testOrder:%=%_q.lua))))

$(build)

tree: ; make -C.. luau
