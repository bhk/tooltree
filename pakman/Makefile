#----------------------------------------------------------------
#  make LuaTest[pakman_q.lua]   run only pakman_q.lua
#  make pakman_q=-V              ... output extra tracing
#----------------------------------------------------------------
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min
include $(smark)/crank-smark.min

#----------------------------------------------------------------

# version stamping
Version += sysinfo
Version.parent = Snip
Version.ext = .lua
Version.num = 0.996
Version.type = /DevBuild
Version.id = $(shell which git > /dev/null && git rev-parse --short HEAD || echo unknown)
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

# Lua execution environment

# Some tests 'cd' during execution, so we use abspath.
LuaEnv.luaPathDirs = $(call <abspath>,. $(luau) $(dir $(call get*,out,Version)) $(lpeg))

# make sure all .lua's are generated before paths are searched
LuaEnv.ooDeps = $(call get*,out,Version)

# Lua test-specific settings

PTest.parent = LuaTest

PTest.exports = $(call inherit) SIMP4
PTest.SIMP4 = $(simp4)/simp4
PTest.deps = $(call inherit) $(call .,SIMP4)

# run unit tests: pakman_q.lua tests the final executable (in pakman_TEST),
#    so there is no need to run it against pakman.lua.
PTest += $(filter-out pakman_q.lua,$(wildcard *_q.lua)) # pakman_q.lua

# build pakman executable

LuaExe += pakman.lua
@pakman = $(call get,out,LuaExe,pakman)

# test pakman executable

PETest += pakman_q.lua
PETest.parent = PTest
PETest.args = pakman=$(call <abspath>,$(@pakman))
PETest.deps = $(call inherit) $(@pakman) $(call get*,out,PTest)

# build HTML docs

SmarkDoc += ReleaseNotes.txt UsersGuide.txt
SmarkDoc.css = pakman.css

# deploy results

Ship.parent = Copy
Ship.dir = out/$v
Ship += $(@pakman) $(call get*,out,SmarkDoc)
Ship.deps = $(call get*,out,PETest)

#----------------------------------------------------------------
$(build)
