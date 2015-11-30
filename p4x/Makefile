include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

#----------------------------------------------------------------

# version stamping
Version += version
Version.ext = .lua
Version.parent = Snip
Version.num = 0.998
Version.type = /DevBuild
Version.id = $(shell git rev-parse --short HEAD)
Version.date = $(shell date +%Y-%m-%d)

define Version.data
return {
   os = "$(<uname>)",
   buildVersion = "$(call .,id)",
   version = $(call .,num),
   versionStr = "$(call .,num)$(call .,type) [$(call .,date) @$(call .,id)]",
   buildDate = "$(call .,date)"
}
endef

# declare Lua directories available to Lua tests and exe's
LuaEnv.luaPathDirs = $(call <abspath>,. $(luau) $(dir $(call get,out,Version,version)))
LuaEnv.ooDeps += $(call get,out,Version,version)

# Run unit tests
SimTest.parent = LuaTest
SimTest += $(wildcard *_q.lua)
SimTest.exports = $(inherit) SIMP4
SimTest.SIMP4 = $(simp4)/simp4
SimTest.deps = $(call inherit) $(call .,SIMP4)

# Build p4x
LuaExe += p4x.lua
@p4x = $(call get,out,LuaExe,p4x)

# Test p4x executable
LuaExeTest += p4x_q.lua
LuaExeTest.parent = SimTest
LuaExeTest.args = p4x=$(call <abspath>,$(@p4x))
LuaExeTest.deps = $(call inherit) $(@p4x)

#
# Package results in 'ship' directory
Ship.parent = Copy
Ship.dir = out/$v
Ship = $(call get,out,LuaExe,p4x)
Ship.deps = $(call get*,out,LuaExeTest)

#----------------------------------------------------------------

$(build)
