# Build shared and static libraries for LPEG.
# Exports libraries and re.lua to .out/$V/exports/...

lpeg-distro ?= ../opensource/lpeg-0.12
lua-exports ?= ../lua/$(VOUTDIR)exports


Alias(default).in = Ship(exports) LuaTest($(lpeg-distro)/test.lua)
exports = SharedLib(@lpeg) Lib(@lpeg) $(lpeg-distro)/re.lua
lpeg = $(wildcard $(lpeg-distro)/*.c)


CC.includes = $(lua-exports)/src
# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror
# lpeg 0.12 and older uses deprecated function luaL_checkint()
CC.flags = -DLUA_COMPAT_APIINTCASTS {inherit}


LuaTest.luaPathDirs = $(lpeg-distro)
LuaTest.luaCPathDirs = $(VOUTDIR)/exports
LuaTest.up = {inherit} Ship(exports)

include ../minion/tooltree.mk
