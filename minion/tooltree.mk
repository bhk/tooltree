# Project-wide build rules

tooltree_minion_dir := $(dir $(lastword $(MAKEFILE_LIST)))

isDebug = $(filter debug,$V)

#
# CC(SOURCE): Compile C files
#

Compile.inherit = T_Compile
T_Compile.inherit = Builder
T_Compile.outExt = .o
T_Compile.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsFile}
T_Compile.depsFile = {@}.d
T_Compile.rule = {inherit}-include {depsFile}$(\n)
T_Compile.flags = {stdFlags} $(if $(isDebug),{dbgFlags},{optFlags}) {warnFlags} {libFlags} $(addprefix -I,{includes})
T_Compile.includes =

T_Compile.stdFlags = -std=c99 -fno-strict-aliasing -fPIC -fstack-protector
T_Compile.dbgFlags = -D_DEBUG -ggdb
T_Compile.optFlags = -O2
T_Compile.warnFlags = -Wall -Wextra -pedantic -Wshadow -Wcast-qual -Wcast-align -Wno-unused-parameter -Werror
T_Compile.libFlags =

CC.inherit = T_CC
T_CC.inherit = Compile
T_CC.compiler = clang
T_CC.warnFlags = {inherit} -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wnested-externs -Wbad-function-cast -Winit-self

#
# Lib(OBJECTS): Create static library
#

Lib.inherit = Builder
Lib.outExt = .lib
Lib.command = ar -rsc {@} {^}

#
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
