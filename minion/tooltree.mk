# Project-wide build rules

tooltree_minion_dir := $(dir $(lastword $(MAKEFILE_LIST)))
#tooltree_dir := $(dir $(patsubst %/,%,$(tooltree_minion_dir)))

# Sub-project locations (relative to other subprojects)

luasources-exports ?= ../opensource/lua-5.2.3
lpegsources-exports ?= ../opensource/lpeg-0.12
lua-exports ?= ../lua/$(VOUTDIR)exports
  luaLib ?= $(lua-exports)/lib/liblua.lib
  luaExe ?= $(lua-exports)/bin/lua
lpeg-exports ?= ../lpeg/$(VOUTDIR)exports
luau-exports ?= ../luau/$(VOUTDIR)exports
smark-exports ?= ../smark/$(VOUTDIR)exports

cfromlua ?= ../crank-lua/cfromlua.lua

# Supported variants

Variants.all = release debug
isDebug = $(filter debug,$V)

Alias(all).in = Variants(Alias(default))
Alias(tree).command = make -C.. V='$V'

#---- Utilities from Crank

# <pquote/punquote> : escape/unescape "%"
<pquote> = $(subst %,^p,$(subst ^,^c,$1))
<punquote> = $(subst ^c,^,$(subst ^p,%,$1))

# return unique words in $1 without re-ordering
<uniqX> = $(if $1,$(firstword $1) $(call $0,$(filter-out $(firstword $1),$1)))
<uniq>  = $(strip $(call <punquote>,$(call <uniqX>,$(call <pquote>,$1))))


#---- Builder classes


# CC(SOURCE): Compile C files
#
Compile.inherit = __Compile
__Compile.inherit = Builder
__Compile.outExt = .o
__Compile.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsFile}
__Compile.depsFile = {@}.d
__Compile.rule = {inherit}-include {depsFile}$(\n)
__Compile.flags = {stdFlags} $(if $(isDebug),{dbgFlags},{optFlags}) {warnFlags} {libFlags} $(addprefix -I,{includes})
__Compile.includes =

__Compile.stdFlags = -std=c99 -fno-strict-aliasing -fPIC -fstack-protector
__Compile.dbgFlags = -D_DEBUG -ggdb
__Compile.optFlags = -O2
__Compile.warnFlags = -Wall -Wextra -pedantic -Wshadow -Wcast-qual -Wcast-align -Wno-unused-parameter -Werror
__Compile.libFlags =

CC.inherit = __CC
__CC.inherit = Compile
__CC.compiler = clang
__CC.warnFlags = {inherit} -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wnested-externs -Wbad-function-cast -Winit-self


# Lib(OBJECTS): Create static library
#
Lib.inherit 	 = Builder
Lib.outExt  	 = .lib
Lib.command 	 = ar -rsc {@} {^}
Lib.inferClasses = CC.c


# SharedLib(OBJECTS): Create a shared library
#
SharedLib.inherit      = Builder
SharedLib.outExt       = .so
SharedLib.command      = clang -o {@} {^} -dynamiclib -undefined dynamic_lookup
SharedLib.inferClasses = CC.c


# Ship(VAR,...): Copy files from @VAR, @..., to a ship directory.
#
#   Note: Ship.in cannot be overridden.  Each argument to Ship must be a
#   variable.  The variable must contain an ingredient list of files to be
#   copied, and the variable's name is the output directory relative to
#   $(VOUTDIR).
#
#   Each `Ship` instance is a single target that depends on zero or more
#   `Ship1` instances.
#
Ship.inherit = Builder
Ship.command = touch {@}
Ship.in = $(foreach a,$(_args),$(patsubst %,Copy(%,dir:$(VOUTDIR)$a/),$(call _expand,@$a)))


# LuaEnv: mixin for defining properties related to the Lua interpreter environment.
#   Shared by LuaTest and LuaToC.
LuaEnv.inherit       = _LuaEnv
_LuaEnv.exports      = LUA_PATH LUA_CPATH {inherit}
_LuaEnv.LUA_PATH     = $(subst $(\s),;,$(call <uniq>,$(foreach d,{luaPathDirs},$(d:%/=%)/?.lua)))
_LuaEnv.LUA_CPATH    = $(subst $(\s),;,$(call <uniq>,$(foreach d,{luaCPathDirs},$(d:%/=%)/?.so)))
_LuaEnv.luaPathDirs  = .
_LuaEnv.luaCPathDirs =
_LuaEnv.preloads     =
_LuaEnv.preloadOpts  = $(addprefix -l ,{preloads})


# LuaTest(SOURCE) : Execute SOURCE using the Lua interpreter.
#
LuaTest.inherit      = LuaEnv _LuaTest
_LuaTest.inherit     = Exec
_LuaTest.outExt      = .ok
_LuaTest.exe         = $(lua-exports)/bin/lua
_LuaTest.up          = {exe}
_LuaTest.command     = {exportPrefix} {exe} {preloadOpts} {^} {args}$(\n)touch {@}


# LuaCC(...) : Variant of CC for building Lua C extension sources
#
LuaCC.inherit  = CC
LuaCC.includes = $(lua-exports)/src {inherit}
LuaCC.stdFlags = {inherit} -Wno-overlength-strings


# LuaExe(LUASOURCES): build an executable with the Lua interpreter, named
#    scripts, and their dependencies (scripts & C extensions). This works
#    much like `LinkC` except that one or more Lua sources are included
#    along with object files.
#
# Implementation notes:
#
#   - LuaToC(...) generates a "main" C source from all Lua sources.
#   - Compile the main C source and other C file inputs using CC(...).
#   - Link the compiled objects with lualib and other discovered libraries.
#
LuaExe.inherit   = _LuaExe
_LuaExe.inherit  = LinkC
_LuaExe.up       = $(luaExe) $(cfromlua)

# Pass all arguments through to LuaToC to generate a single C file.
_LuaExe.inX = $(call _expand,{in},in)
_LuaExe.mainC = LuaToC($(subst $(\s),$;,$(filter %.lua,{inX})))
_LuaExe.inIDs = LuaCC({mainC}) $(luaLib) $(patsubst %.c,LuaCC(%.c),$(filter-out %.lua,{inX}))
_LuaExe.inPairs = $(foreach i,{inIDs},$i$(if $(filter %$],$i),$$$(call get,out,$i)))

# The link command line invokes cfromlua using the `$(...)` shell construct
# to extract the list of discovered native extensions from the main C file,
# and to write their dependencies into a .d file.  (These are not known at
# Make rule generation time.)
_LuaExe.command = {inherit} $$( $(luaExe) $(cfromlua) --readlibs -MF {depsFile} -MT {@} -MP $(call get,out,{mainC}) )
_LuaExe.depsFile = {@}.d


# LuaToC(SOURCES) : Bundle Lua SOURCES with all their dependencies in a
#    single C file.
#
LuaToC.inherit   = LuaEnv _LuaToC
_LuaToC.inherit  = Exec
_LuaToC.outExt   = .c
_LuaToC.command  = {exportPrefix} $(luaExe) $(cfromlua) -o {@} {flags} $(addprefix -l ,{preloads}) -MF {depsFile} -MP -Werror $(foreach l,{openLibs},--open=$l) -- {^}
_LuaToC.up       = $(luaExe) $(cfromlua)
_LuaToC.depsFile = {@}.d
_LuaToC.flags    = --minify
_LuaToC.openLibs =

# We presume LuaToC is used by LuaExe, and that certain properties will be
# inherited from the corresponding instance of LuaExe.
# _LuaToC.luaIn     = $(call get,luaIn,LuaExe,$I)
# _LuaToC.luaLibs   = $(call get,luaLibs,LuaExe,$I)#  --> openLibs
# _LuaToC.preloads  = $(call get,preloads,LuaExe,$I)


include $(tooltree_minion_dir)minion.mk
