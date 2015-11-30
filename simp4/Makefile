include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

#----------------------------------------------------------------

# lua source dirs used by unit tests and simp4
LuaEnv.luaPathDirs = $(call <abspath>,. $(luau) $(luau) $(lpeg))

# Run tests
LuaTest += $(wildcard *_q.lua)

# Build simp4
LuaExe += simp4.lua
@simp4 = $(call get,out,LuaExe,simp4)

# Test simp4
LuaExeTest += simp4_q.lua
LuaExeTest.parent = LuaTest
LuaExeTest.args = $(@simp4)
LuaExeTest.deps = $(@simp4) $(call get*,out,LuaTest)

# Deploy results
Ship.parent = Copy
Ship.dir = out/$v
Ship = $(@simp4)

#----------------------------------------------------------------

$(build)
