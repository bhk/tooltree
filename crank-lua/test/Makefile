# this can vary by $v, so it determines which $v we are testing
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min

OK.parent = Gen
OK.ext = .ok
OK.command = $(call .,run) && touch $(call .,out)
OK.deps = $(call get*,out,LuaTest LuaExe)

LuaEnv.luaPathDirs = . ..

### LuaTest test cases

# ASSERT:
#  - LuaTest items are invoked
#  - LUA_PATH is exported when unit tests are run (default = "./?.lua")
#
LuaTest += a

# ASSERT:
#  - LuaTest items are invoked
#  - LUA_PATH is properly exported
#  - `LuaTest.in` specifies file to execute
#  - `LuaTest.args` is passed on the command line
#
LuaTest += a
LuaTest[a].in = writepath.lua
LuaTest[a].luaPathDirs = . otherdir
LuaTest[a].args = $(call .,pathfile)
LuaTest[a].pathfile = $(call .,OUTDIR)path.txt


# ASSERT: LuaTest was actually executed
Test += a
Test[a].in = $(call get,out,LuaTest,a)
Test[a].test = grep -q '<./?.lua;otherdir/?.lua>' $(call get,pathfile,LuaTest,a)


# ASSERT: `LuaTest.preloads` modules are executed on startup
LuaTest += b
LuaTest[b].in = cfl.lua
LuaTest[b].preloads = pre
LuaTest[b].args = a


### LuaExe

LuaExe += cfl.lua
LuaExe[cfl.lua].preloads = pre


# ASSERT: cfl.lua has builds and runs correctly
#   - Not dependent on LUA_PATH
#   - `LuaExe.preloads` modules are executed on startup
#   - Command-line args are available to the exe
#
RunCFL += LuaExe
RunCFL.parent   = Test
RunCFL.in       = $(call get,out,$I,cfl.lua)
RunCFL.exports  = LUA_PATH
RunCFL.LUA_PATH = nosuchdir/?
RunCFL.runCmd   = $<
RunCFL.test     = $(call v.,c-emulator) $(call .,runCmd) x | grep 'x11-' > /dev/null


# ASSERT: LuaToC bundles only one copy when a files is required twice (via
# require or requirefile)
#
Test += bundle
Test[bundle].in = $(call get,out,LuaToC,cfl.lua)
Test[bundle].test = ( grep This.is.dep.lua $< | wc -l | grep 1 && grep This.is.data.txt $< | wc -l | grep 1 ) > /dev/null


# ASSERT: requirefile() dependencies properly generated.  Note that dep.lua
#    appears twice due to being used in require() and requirefile().  The
#    "./" prefixes come from LUA_PATH.
#
Test += deps
Test[deps].in = $(call get,out,LuaToC,cfl.lua)
Test[deps].test = grep 'LuaToC/cfl.c: cfl.lua ./dep.lua ./pre.lua ./dep.lua ./data.txt$$' $(call get,depFile,LuaToC,cfl.lua) > /dev/null


### LuaToLua

# ASSERT: LuaToLua collects all dependencies into one Lua source file
# ASSERT: LuaToC non-minified version works (retained comments can affect parsing).

LuaToLua += cfl.lua
LuaToLua[cfl.lua].options = $(filter-out --minify,$(call inherit))


# ASSERT: cfl.lua runs correctly as a bundled Lua file
#
RunCFL += LuaToLua
RunCFL[LuaToLua].runCmd = $(call get,luaHostExe,LuaConfig,x) $<


$(build)
