# Project-wide build rules

tooltree_minion_dir := $(dir $(lastword $(MAKEFILE_LIST)))
#tooltree_dir := $(dir $(patsubst %/,%,$(tooltree_minion_dir)))

#----------------------------------------------------------------
# Project-wide configuration
#----------------------------------------------------------------

luasources-exports ?= ../opensource/lua-5.2.3
lpegsources-exports ?= ../opensource/lpeg-0.12
lua-exports ?= ../lua/$(VOUTDIR)exports
  luaLib ?= $(lua-exports)/lib/liblua.lib
  luaExe ?= $(lua-exports)/bin/lua
lpeg-exports ?= ../lpeg/$(VOUTDIR)exports
luau-exports ?= ../luau/$(VOUTDIR)exports
smark-exports ?= ../smark/$(VOUTDIR)exports
build-lua-exports ?= ../build-lua
monoglot-exports ?= ../monoglot/$(VOUTDIR)exports

cfromlua ?= ../build-lua/cfromlua.lua

# Supported variants

Variants.all = release debug
isDebug = $(filter debug,$V)

Alias(all).in = Variants(Alias(default))
Alias(tree).command = make -C.. V='$V'


#----------------------------------------------------------------
# Utility functions
#----------------------------------------------------------------

# <pquote/punquote> : escape/unescape "%"
<pquote> = $(subst %,^p,$(subst ^,^c,$1))
<punquote> = $(subst ^c,^,$(subst ^p,%,$1))

# return unique words in $1 without re-ordering
<uniqX> = $(if $1,$(firstword $1) $(call $0,$(filter-out $(firstword $1),$1)))
<uniq>  = $(strip $(call <punquote>,$(call <uniqX>,$(call <pquote>,$1))))
_uniq   = $(strip $(call <punquote>,$(call <uniqX>,$(call <pquote>,$1))))


#----------------------------------------------------------------
# Builder classes 
#----------------------------------------------------------------

# TODO:
#  - CleanGoal (expands indirections, knows aliases and warns)
#    _Clean only works on instances
#  - skip phony targets (isPhony?)
#  - after minion refactor, remove .inFiles & replace (expand {in}) with {inX}
Clean.inherit = _Clean
_Clean.inherit = Phony
_Clean.in =
_Clean.targets = $(filter %$],$(_args))# protect against being used on a plain file
_Clean.depsIDs = $(patsubst %,Clean(%),$(subst $(\s),$;,$(filter %$],$(call get,needs,{targets}))))
_Clean.command = $(patsubst %,rm -f %$(\n),$(call get,out,{targets}))


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


# Exe(OBJECTS): Create an executable.
#
Exe.inherit = LinkC
Exe.compiler = clang


# CTest(foo.c) -> Exe(foo.c) -> CC(foo.c)
CTest.inherit = Test
CTest.inferClasses = Exe.c


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


include $(tooltree_minion_dir)minion.mk
