# This project builds the lua interpreter, luac, and liblua.
# Exported binaries and sources are deployed to .out/$V/exports/...

# Configuration
#   Define `lua-useReadline` to use the readline library in the lua
#   interpreter.  Readline is big and slows startup (as when running unit
#   tests), and provides no benefit for sessions in an Emacs shell.
# lua-useReadline = 1

Alias(default).in = Ship(exports/bin,exports/lib,exports/src)

exports/bin = CExe(lua) CExe(luac)
exports/lib = Lib(liblua)
exports/src = $(patsubst %,$(package.luasources)/src/%.h, lua luaconf lualib lauxlib)

CExe(lua).in = $(package.luasources)/src/lua.c Lib(liblua)
CExe(luac).in = $(package.luasources)/src/luac.c Lib(liblua)
Lib(liblua).in = $(filter-out %/lua.c %/luac.c,$(wildcard $(package.luasources)/src/*.c))

# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror
CC.srcFlags = {inherit} -DLUA_USE_POSIX -D_GNU_SOURCE -DLUA_USE_DLOPEN

ifdef lua-useReadline
  CC.srcFlags += -DLUA_USE_READLINE
  CExe(lua).libFlags = -lreadline # needed for MacOS
endif

minionCache = default
include ../build/tooltree.mk
