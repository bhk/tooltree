# Build shared and static libraries for LPEG.
# Exports libraries and re.lua to .out/$V/exports/...

Alias(default).in = Ship(exports) LuaTest($(lpegsources-exports)/test.lua)

exports = SharedLib(@lpeg) Lib(@lpeg) $(lpegsources-exports)/re.lua
lpeg = $(wildcard $(lpegsources-exports)/*.c)

CC.includes = $(lua-exports)/src
# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror
# lpeg 0.12 and older uses deprecated function luaL_checkint()
CC.flags = -DLUA_COMPAT_APIINTCASTS {inherit}

LuaTest.luaPathDirs = $(lpegsources-exports)
LuaTest.luaCPathDirs = $(dir $(call get,out,SharedLib(@lpeg)))
LuaTest.up = {inherit} SharedLib(@lpeg)

include-deps = $(build-lua-exports)/build-lua.mk
include ../build/tooltree.mk
