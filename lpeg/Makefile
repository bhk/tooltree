# Build shared and static libraries for LPEG.
# Exports libraries and re.lua to .out/$V/exports/...

default = Ship(exports) LuaTest($(package.lpegsources)/test.lua)

exports = SharedLib(@lpeg) Lib(@lpeg) $(package.lpegsources)/re.lua
lpeg = @$(package.lpegsources)/*.c

CC.includes = $(package.lua)/src
# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror
# lpeg 0.12 and older uses deprecated function luaL_checkint()
CC.srcFlags = -DLUA_COMPAT_APIINTCASTS {inherit}

LuaTest.luaPathDirs = $(package.lpegsources)
LuaTest.luaCPathDirs = $(dir {SharedLib(@lpeg).out})
LuaTest.up = {inherit} SharedLib(@lpeg)

include ../build/tooltree.mk
