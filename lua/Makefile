# This project builds Lua from sources and exports libraries, executables,
# and headers.  Build results will be found in out/release/... .

include .config
include $(crank)/crank.min
include $(crank-c)/crank-c.min

ifeq "$(call v.,c-targetOS)" "WinNT"
  Compile.flag-luaOpts  = -D_CRT_SECURE_NO_DEPRECATE -DLUA_BUILD_AS_DLL
else
  Compile.flag-luaOpts  = -DLUA_USE_POSIX -D_GNU_SOURCE -DLUA_USE_DLOPEN
  Compile.flag-readline = -DLUA_USE_READLINE
  Exe.flag-readline     = -lreadline
endif

# flag set to 'readline' if a member of $V or v.luaReadline is set
readlineFlag = $(filter readline,$(V.flags) $(if $(call v.,luaReadline),readline))

# flags common to Compile and Exe
commonFlags    = luaOpts $(readlineFlag)

# Use `nowarn` because we want to use the original sources unmodified
Compile.flags = $(call inherit) $(commonFlags) nowarn nopedantic
Exe.flags     = $(call inherit) $(commonFlags) lm

# Ordinarily .in==$I==filename but we define it differently to make $I
# simpler.  This way, we can type "make Compile[lua.c]"
Compile.in = $(lua-distro)/src/$I

#### Build libraries and executables

# The executables incorporate static libraries, EXCEPT lua.exe on Windows,
# which uses liblua.dll. This allows it to load Lua C extensions, which will
# also have to link against liblua.dll.

LuaCs = $(notdir $(wildcard $(lua-distro)/src/*.c))

ifeq "$(call v.,c-targetOS)" "WinNT"
  SharedLib += liblua
  SharedLib[liblua].in = $(filter-out luac.c lua.c print.c,$(LuaCs))
endif

Lib += liblua
Lib[liblua].in = $(filter-out luac.c lua.c print.c,$(LuaCs))

Exe += lua
Exe[lua].in = lua.c $(or $(call get*,implib,SharedLib),$(call get,out,Lib,liblua))
Exe[lua].flags = $(call inherit) dlopen

Exe += luac
Exe[luac].in = luac.c $(filter print.c,$(LuaCs)) $(call get,out,Lib,liblua)

#### Copy results to ship directory

Ship/bin.parent = Copy
Ship/bin.dir = out/$v/bin
Ship/bin = $(call get*,out,Exe) $(call get*,dlib,SharedLib)

Ship/lib.parent = Copy
Ship/lib.dir = out/$v/lib
Ship/lib = $(call get*,out,Lib) $(call get*,implib,SharedLib)

Ship/src.parent = Copy
Ship/src.dir = out/$v/src
Ship/src = $(patsubst %,$(lua-distro)/src/%.h, lua luaconf lualib lauxlib)


$(build)
