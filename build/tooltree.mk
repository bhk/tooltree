# Project-wide build rules

tooltree_build_dir := $(dir $(lastword $(MAKEFILE_LIST)))
_tt := $(patsubst %build/,%,$(tooltree_build_dir))

#----------------------------------------------------------------
# Variant configuration
#----------------------------------------------------------------

Variants.all = release debug
V(debug).debug = 1

#----------------------------------------------------------------
# Package configuration
#----------------------------------------------------------------
#
# Below are the packages known to Tooltree.  Makefiles external to tooltree
# may define their own packages before including tooltree.mk.  To define a
# package, e.g. PKG, define a variable identifying its location;
#
#     PKG-package = SOURCES
#
# *If* the package has a build step, define:
#
#     PKG-outdir = OUTDIR_REL
#
# `PKG-exports` will be defined as $(PKG-package)$(PKG-outdir).  This shoud
# name a directory that will contain the build results (after a successful
# build).  OUTDIR_REL may be completely empty; defining the variable
# indicates there is a build step.
#
# If the package does not have a build step, `PKG-exports` will be defined
# as $(PKG-package).
#

bench-package = $(_tt)bench
bench-deps = luau build-lua monoglot lpeg

build-js-package = $(_tt)build-js
build-js-outdir = /$(VOUTDIR)exports
build-js-deps = build-lua luau lpeg

build-lua-package = $(_tt)build-lua
build-lua-outdir =
build-lua-deps = lua

jsu-package = $(_tt)jsu
jsu-deps = build-js

lpeg-package = $(_tt)lpeg
lpeg-outdir = /$(VOUTDIR)exports
lpeg-deps = build-lua lua lpeg

lpegsources-package = $(_tt)opensource/lpeg-0.12

lua-package = $(_tt)lua
lua-outdir = /$(VOUTDIR)exports
lua-deps = luasources

luasources-package = $(_tt)opensource/lua-5.2.3

luau-package = $(_tt)luau
luau-outdir = /$(VOUTDIR)exports
luau-deps = build-lua lua

mdb-package = $(_tt)mdb
mdb-outdir = /$(VOUTDIR)exports
mdb-deps = luau build-lua monoglot lpeg build-js jsu

monoglot-package = $(_tt)monoglot
monoglot-outdir = /$(VOUTDIR)exports
monoglot-deps = luau build-lua lpeg lua

pages-package = $(_tt)pages
pages-outdir =
pages-deps = smark monoglot build-lua luau mdb crank-js jsu

smark-package = $(_tt)smark
smark-outdir = /$(VOUTDIR)exports
smark-deps = luau build-lua lpeg

webdemo-package = $(_tt)webdemo
webdemo-outdir =
webdemo-deps = luau build-lua lua monoglot lpeg

#----------------------------------------------------------------
# Tooltree function, class, and alias definitions
#----------------------------------------------------------------

Alias(all).in = Variants(Alias(default))
Alias(tree).command = make -C.. V='$V'

# _pquote/_punquote : escape/unescape "%"
_pquote = $(subst %,^p,$(subst ^,^c,$1))
_punquote = $(subst ^c,^,$(subst ^p,%,$1))

# return unique words in $1 without re-ordering
_uniqX = $(if $1,$(firstword $1) $(call $0,$(filter-out $(firstword $1),$1)))
_uniq = $(strip $(call _punquote,$(call _uniqX,$(call _pquote,$1))))

# return $1 if variable $1 is defined
_defined = $(if $(filter undefined,$(origin $1)),,$1)

# evaluate property $1 for current variant
_vprop = $($(or $(call _defined,V($V).$1),V.$1))

_isDebug = $(call _vprop,debug)


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
__Compile.flags = {stdFlags} $(if {isDebug},{dbgFlags},{optFlags}) {warnFlags} {libFlags} $(addprefix -I,{includes})
__Compile.includes =

__Compile.stdFlags = -std=c99 -fno-strict-aliasing -fPIC -fstack-protector
__Compile.isDebug = $(_isDebug)
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
Lib.inherit = Builder
Lib.outExt = .lib
Lib.command = ar -rsc {@} {^}
Lib.inferClasses = CC.c


# SharedLib(OBJECTS): Create a shared library
#
SharedLib.inherit = Builder
SharedLib.outExt = .so
SharedLib.command = clang -o {@} {^} -dynamiclib -undefined dynamic_lookup
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
#   The ship directory is $(VOUTDIR)VAR.
#
#   Note: {in} cannot be overridden in instances or subclasses.  Each
#   argument to Ship must be a variable name.  Each variable contains an
#   ingredient list of files to be copied.
#
#   Each `Ship` instance is a single target that depends on zero or more
#   `Copy` instances.
#
Ship.inherit = Phony
Ship.in = $(foreach a,$(_args),$(patsubst %,Copy(%,dir:$(VOUTDIR)$a/),$(call _expand,@$a)))


#----------------------------------------------------------------
# Process packages
#----------------------------------------------------------------

all-packages = $(patsubst %-package,%,$(filter %-package,$(.VARIABLES)))

# Define `PKG-sources` and `PKG-exports` variables
_export_package = \
  $(eval $1-exports = $$($1-package)$(subst |,/,$(value $1-outdir)))

$(foreach _pkg,$(all-packages),$(call _export_package,$(_pkg)))

minion_start = 1
include $(_tt)build/minion.mk

# include-deps : a list of makefiles that are to be included just prior to
#    the rule-generation phase, after Minion definitions have been loaded.
#    This enables loading makefiles exported from other packages.
#    $(PACKAGE-exports) variables generally cannot be evaluated prior to
#    loading of MINION because their definitions often include $(VOUTDIR) or
#    $V which are defined or defaulted by Minion.
$(eval include $(include-deps))

$(minion_end)
