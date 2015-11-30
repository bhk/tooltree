# This project builds LPeg from sources and exports a library (liblpeg.lib)
# and a source file (re.lua).  Build results are placed in out/release/...

include .config
include $(crank)/crank.min
include $(crank-c)/crank-c.min
include $(crank-lua)/crank-lua.min


# Configuration flags

Compile.flags = $(call inherit) nowarn

# lpeg 0.12 and older uses deprecated function luaL_checkint()
Compile.flags += -DLUA_COMPAT_APIINTCASTS

#### Build the object files

LuaExt = lpeg

LuaExtLib[lpeg].in = $(wildcard $(lpeg)/*.c)

#### Test

# Execute unit tests
# Note: If we are building LPeg 0.10.2, we skip testing because
#       it depends on Lua 5.1's strict.lua which depends on
#       loadstring(), which was removed in Lua 5.2
LuaTest = $(if $(findstring 0.10.2,$(lpeg)),,$(lpeg)/test.lua)
LuaTest.luaPathDirs = $(lpeg)

#### ship object & source

Ship.parent = Copy
Ship.dir = out/$v
Ship += $(call get*,out,LuaExt) $(lpeg)/re.lua


$(build)
