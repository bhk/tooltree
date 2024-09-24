# Build shared and static libraries for LPEG.
# Exports libraries and re.lua to .out/$V/exports/...

Alias(default).in = Ship(exports) LuaTest($(package.lpegsources)/test.lua)

exports = SharedLib(@lpeg) Lib(@lpeg) $(package.lpegsources)/re.lua
lpeg = $(wildcard $(package.lpegsources)/*.c)

CC.includes = $(package.lua)/src
# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror
# lpeg 0.12 and older uses deprecated function luaL_checkint()
CC.srcFlags = -DLUA_COMPAT_APIINTCASTS {inherit}

LuaTest.luaPathDirs = $(package.lpegsources)
LuaTest.luaCPathDirs = $(dir $(call get,out,SharedLib(@lpeg)))
LuaTest.up = {inherit} SharedLib(@lpeg)

includeImports = build-lua/build-lua.mk
include ../build/tooltree.mk
