include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

#----------------------------------------------------------------

# version stamping
Version       += ccov cmet
Version.parent = Snip
Version.type   = dev
Version.ext    = -ver.lua
Version.id     = $(shell git rev-parse --short HEAD)
Version.data   = return "$(call .,num)/$(call .,type)@$(call .,id) [$(shell date)]"
Version[ccov].num = 1.1
Version[cmet].num = 1.1
Version.valueDeps =

# LuaEnv properties are inherited by LuaTest and CFromLua
LuaEnv.luaPathDirs = . $(luau) $(dir $(call get,out,Version,ccov))

# Order-only ensures that generated Lua sources are built before we run any
# Lua. Actual dependencies will be generated when each target is first built.
LuaEnv.ooDeps += $(call get*,out,Version)

# Run all unit tests

LuaTest        += $(wildcard *_q.lua)

# Build exes

LuaExe += cmet.lua ccov.lua

# Execute unit tests against the built executable (when passed an argument,
# they invoke the executable via popen).

ETest       += cmet ccov
ETest.parent = LuaTest
ETest.in     = $I_q.lua
ETest.args   = $(call get,out,LuaExe,$I)
ETest.deps   = $(inherit) $(wildcard test/$I*) $(call get*,out,LuaTest LuaExe)

# Build ship dir

Ship.parent = Copy
Ship.dir = out/$v
Ship = $(call get*,out,LuaExe)
Ship.deps = $(call get*,out,ETest)

#----------------------------------------------------------------

$(build)
tree: ; make -C.. ctools
