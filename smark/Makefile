# External dependencies
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min
include crank-smark.min

#----------------------------------------------------------------

# directories to search for .lua files
LuaEnv.luaPathDirs = . $(luau) $(lpeg) $(luau)

# Run tests
LuaTest += $(wildcard *_q.lua)
LuaTest.luaPathDirs = $(call <abspath>,$(call inherit)) # some tests call `chdir`

# Generate Smark
LuaExe += smark.lua
@smark = $(call get,out,LuaExe,smark)

# Run smark_q.lua on the built *executable*
SmarkTest.parent = LuaTest
SmarkTest = smark_q.lua
SmarkTest.args = --cmd='$(call <abspath>,$(@smark))'
SmarkTest.deps = $(@smark)

# Generate HTML doc if this is not a cross-compiled variant
SmarkDoc = $(if $(call v.,c-noExec),,smark.txt)
SmarkDoc.exe = $(@smark)

# Package results in 'ship' directory
Ship.parent = Copy
Ship.dir = out/$v
Ship = $(@smark) smark.txt $(call get*,out,SmarkDoc) crank-smark.min
Ship.deps = $(call get*,out,SmarkTest)

# Make unit tests run in a precise order (debug lower-level ones first)
testOrder = smarkmisc source markup mscgen html2d smark_art smark_lua smark_table smark
orderDeps = $(if $1,$(if $2,$(\n)LuaTest[$(word 1,$1)].ooDeps += $2) \
    $(call orderDeps,$(wordlist 2,999,$1),$(call get,out,LuaTest,$(word 1,$1)) $2))
$(call <eval>,$(foreach v,$V,$(call orderDeps,$(testOrder:%=%_q.lua))))

#----------------------------------------------------------------

$(build)

tree: ; make -C.. smark
