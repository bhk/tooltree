# This project builds the lua interpreter, luac, and liblua.
# Exported binaries and sources are deployed to .out/$V/exports/...

# Configuration
#   Define `lua-useReadline` to use the readline library in the lua
#   interpreter.  Readline is big and slows startup (as when running unit
#   tests), and provides no benefit for sessions in an Emacs shell.
# lua-useReadline = 1

Alias(default).in = Ship(exports/bin,exports/lib,exports/src)

exports/bin = CExe(@lua) CExe(@luac)
exports/lib = Lib(CC@liblua)
exports/src = $(patsubst %,$(package.luasources)/src/%.h, lua luaconf lualib lauxlib)
lua-cfiles = $(wildcard $(package.luasources)/src/*.c)
lua = $(filter-out %/luac.c %/print.c,$(lua-cfiles))
luac = $(filter-out %/lua.c,$(lua-cfiles))
liblua = $(filter-out %/lua.c %/luac.c %/print.c,$(lua-cfiles))

CC.srcFlags = {inherit} -DLUA_USE_POSIX -D_GNU_SOURCE -DLUA_USE_DLOPEN

ifdef lua-useReadline
  CC.srcFlags += -DLUA_USE_READLINE
  CExe(@lua).libFlags = -lreadline # needed for MacOS
endif

# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror

include ../build/tooltree.mk
