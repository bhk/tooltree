# This project builds the lua interpreter, luac, and liblua.
# Exported binaries and sources are deployed to .out/$V/exports/...

# Set `lua-useReadline` to use the readline library in the lua interpreter.
# Readline is big and slows startup (as when running unit tests), and
# provides no benefit for interactive sessions in an Emacs shell.

# Configuration

lua-distro = ../opensource/lua-5.2.3
#lua-useReadline = 1

Alias(default).in = Ship(exports/bin,exports/lib,exports/src)

lua-cfiles = $(wildcard $(lua-distro)/src/*.c)
lua = $(filter-out %/luac.c %/print.c,$(lua-cfiles))
luac = $(filter-out %/lua.c,$(lua-cfiles))
liblua = $(filter-out %/lua.c %/luac.c %/print.c,$(lua-cfiles))
exports/bin = LinkC(@lua) LinkC(@luac)
exports/lib = Lib(CC@liblua)
exports/src = $(patsubst %,$(lua-distro)/src/%.h, lua luaconf lualib lauxlib)

CC.stdFlags = {inherit} -DLUA_USE_POSIX -D_GNU_SOURCE -DLUA_USE_DLOPEN

ifdef lua-useReadline
  CC.stdFlags += -DLUA_USE_READLINE
  LinkC(@lua).flags = {inherit} -lreadline # needed for MacOS
endif

# Avoid project-wide warnings so we can use the original sources unmodified
CC.warnFlags = -Werror

include ../minion/tooltree.mk
