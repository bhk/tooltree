# Test cfromlua and Lua-related builder classes.

Alias(default).in = @tests

# These settings are intended for cfl.lua
#   Inherited by LuaToC, LuaToLua, LuaExec, LuaTest, ...
LuaEnv.luaPathDirs = . test nosuchdir
LuaEnv.preloads = pre
#   Inherited by LuaExec, LuaTest, ...
LuaCmd.execArgs = ARG


# ASSERT: LuaTest() executes a Lua file and passes LUA_PATH correctly
tests += LuaTest(A)
LuaTest(A).in = test/cfl.lua
LuaTest(A).arg = "quiet"


# ASSERT: LuaExec() captures output
# ASSERT: LuaExec() passes LUA_PATH correctly
# ASSERT: LuaExec() conveys {preloads}
tests += Test(B)
Test(B).in = LuaExec(test/cfl.lua)
Test(B).exec = grep -q 'P1,D1,ARG,1,BOGUS,BOGUS' {<} $(\n)\
               grep -q '<./?.lua;test/?.lua;nosuchdir/?.lua>' {<}


# ASSERT:  LuaExec(LuaToLua(CFL)) == LuaExec(CFL)
# ASSERT:  LuaToLua provides `requirefile` implementation
tests += Test(C)
Test(C).in = LuaExec(LuaToLua(test/cfl.lua))
Test(C).exec = grep -q 'P1,D1,ARG,1,.. dep.lua,This' {<} $(\n)\
               grep -q '<./?.lua;test/?.lua;nosuchdir/?.lua>' {<}


# ASSERT: LuaToC() bundles a single copy of a module that's required twice
# ASSERT: requirefile() dependencies are properly generated.
#    Note that dep.lua appears twice due to being used in require() and
#    requirefile().  The "./" prefixes come from LUA_PATH.
tests += Test(D)
Test(D).in = LuaToC(test/cfl.lua)
Test(D).exec = \
   grep [-][-].dep.lua {<} | wc -l | grep -q 1 $(\n)\
   grep This.is.data.txt {<} | wc -l | grep -q 1 $(\n)\
   grep -q 'test/cfl.c: test/cfl.lua test/dep.lua test/pre.lua test/dep.lua test/data.txt$$' $(call get,depsFile,{in})


# ASSERT:  Exec(LuaExe(CFL)) == LuaExec(LuaToLua(CFL))
# ASSERT: `luaTest.preloads` are executed on startup
tests += Test(E)
Test(E).in = Exec(LuaExe(test/cfl.lua))
Test(E).exec = grep -q 'P1,D1,ARG,1,.. dep.lua,This' {<}
Exec(LuaExe(test/cfl.lua)).execArgs = ARG

include build-lua.mk
include ../minion/tooltree.mk
