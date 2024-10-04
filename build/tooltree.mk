# Project-wide build rules
#
# User makefiles typically include this file after defining all their
# build targets using Minion variables or Make rules.
#
# User makefiles may also define the following:
#
# $(this-package) = name of current package; default = name of current dir.
#    This comes into use during `make imports` or `make deep`.
#
# $(include-imports) is a list of paths to makefiles that are supplied by
#    imported packages and must be included.  The first element in each path
#    is the name of the exporting package, and it will be replaced with that
#    package's export directory.  For example, 'p1/defs.mk' expands to
#    `$(package.p1)/defs.mk` which might look something like
#    '../p1/.out/exports/defs.mk.
#
#    These makefiles are included after minion.mk has been loaded because
#    $(package.PKG) variables generally include $(VOUTDIR) or $V which are
#    defined or defaulted by Minion.
#
# Package descriptions
#
#    Define packages using the following variables:
#
#    $(package.NAME.dir) = the package directory.
#    $(package.NAME.imports) = other packages that must be built this one.
#    $(package.NAME.outdir) = a path RELATIVE TO `DIR` to a directory that
#         will contain exports (build results) after the package is built.
#         If empty or undefined, the entire package is exported.  If
#         undefined, there is no build step.
#
#    Tooltree will compute the following for each package imported
#    by the package currently being built:
#
#    $(package.NAME) = path to the export directory.
#
_tt := $(patsubst %build/,%,$(dir $(lastword $(MAKEFILE_LIST))))

# Use parallel builds for all projects
MAKEFLAGS += -j9 -Rr

#----------------------------------------------------------------
# Variant configuration
#----------------------------------------------------------------

Variants.all = release debug
V(debug).debug = 1

#----------------------------------------------------------------
# Package configuration
#----------------------------------------------------------------
#
# Below are descriptions of the packages known to Tooltree.
#

package.bench.dir = $(_tt)bench/
package.bench.imports = luau build-lua monoglot lpeg

package.build-js.dir = $(_tt)build-js/
package.build-js.outdir = $(VOUTDIR)exports
package.build-js.imports = build-lua luau lpeg

package.build-lua.dir = $(_tt)build-lua/
package.build-lua.outdir =
package.build-lua.imports = lua

package.jsu.dir = $(_tt)jsu/
package.jsu.imports = build-js

package.lpeg.dir = $(_tt)lpeg/
package.lpeg.outdir = $(VOUTDIR)exports
package.lpeg.imports = build-lua lua lpegsources

package.lpegsources.dir = $(_tt)opensource/lpeg-0.12

package.lua.dir = $(_tt)lua/
package.lua.outdir = $(VOUTDIR)exports
package.lua.imports = luasources

package.luasources.dir = $(_tt)opensource/lua-5.2.3

package.luau.dir = $(_tt)luau/
package.luau.outdir = $(VOUTDIR)exports
package.luau.imports = build-lua lua

package.mdb.dir = $(_tt)mdb/
package.mdb.outdir = $(VOUTDIR)exports
package.mdb.imports = luau build-lua monoglot lpeg build-js jsu

package.monoglot.dir = $(_tt)monoglot/
package.monoglot.outdir = $(VOUTDIR)exports
package.monoglot.imports = luau build-lua lpeg lua

package.pages.dir = $(_tt)pages/
package.pages.outdir = $(VOUTDIR)
package.pages.imports = smark monoglot build-lua luau mdb crank-js jsu

package.smark.dir = $(_tt)smark/
package.smark.outdir = $(VOUTDIR)exports
package.smark.imports = luau build-lua lpeg

package.webdemo.dir = $(_tt)webdemo/
package.webdemo.outdir = .
package.webdemo.imports = luau build-lua lua monoglot lpeg

#----------------------------------------------------------------
# Tooltree function, class, and alias definitions
#----------------------------------------------------------------

Alias(all).in = Variants(Alias(default))
Alias(deep).in = Package($(this-package))
Alias(clean-deep).in = CleanPackage($(this-package))
Alias(graph).in = Graph(Alias(default))
Alias(imports).in = Package@package.$(this-package).imports
Alias(clean-imports).in = CleanPackage@package.$(this-package).imports

this-package ?= $(notdir $(abspath .))

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


# Package(PACKAGE) : Package PACKAGE
#
Package.inherit = _Package
_Package.inherit = IsPhony Builder
_Package.outExt = .out
_Package.inPairs = # no dependencies (for now)
_Package.deps = $(foreach P,{imports},$(_class)($P))
_Package.command = $(if {hasMake},{makeCommand})
_Package.message = $(if {hasMake},{inherit})
_Package.makeCommand = @( cd {buildDir} && $(MAKE) ) > {@} 2>&1 || printf '**FAILED: see {@} for log\nOr: cd {buildDir} && make\n'

# Package properties
_Package.buildDir = $(package.$(_arg1).dir)
_Package.imports = $(package.$(_arg1).imports)
_Package.hasMake = $(package.$(_arg1).outdir)

CleanPackage.inherit = _CleanPackage
_CleanPackage.inherit = Package
_CleanPackage.command = $(if {hasMake},@cd {buildDir} && rm -rf .out)


# Graph(INSTANCES) : Draw a graph of dependencies of instances
#
# Set Graph_FILES=1          to include explicit files (but not implicit deps)
# Set Graph_IGNORE=CLASSES   to omit certain classes
#
Graph.inherit = Phony
Graph.in =
Graph.inExp = $(call Graph_filter,$(call _expand,$(_args)))
Graph.rule = {@}: ; @true $$(info $$(call Graph_draw,Graph_get-,$$(call Graph_trav,Graph_get-children,$(call _escArg,{inExp}))))

Graph_filter = $(filter-out $(patsubst %,%$[%,$(Graph_IGNORE)),$(filter $(if $(Graph_FILES),%,%$]),$1))
Graph_get-children = $(call Graph_filter,$(call get,needs,$1))
Graph_get-name = $(patsubst Package(%),%,$(patsubst Alias(%),%,$1))
# see graph.scm for source...
Graph_trav = $(if $(word 1,$2),$(call $0,$1,$(call $1,$(word 1,$2)) $(wordlist 2,9999,$2),$(filter-out $(word 1,$2),$3) $(word 1,$2)),$3)
Graph_draw = $(if $2,$(call $0,$1,$(wordlist 2,9999,$2),$(subst ``,` ,$(filter-out %9,$(subst `  ,``,$(patsubst `,` ,$(subst `$(word 1,$2)`,`,$3) `$(subst $(\s),,$(addsuffix `,$(call $1children,$(word 1,$2)))) 9)))),$4$(foreach ;,$3,$(if $(filter `,$;), ,|)  )$(\n)$(foreach ;,$3,$(if $(findstring `$(word 1,$2)`,$;),+->,$(if $(filter `,$;), ,|)  ))$(if $3, )$(call $1name,$(word 1,$2))$(\n)),$4)# Emacs wants a closing `

#----------------------------------------------------------------
# Process packages
#----------------------------------------------------------------

# Access $(package.NAME) and validate NAME
_pkg = $(or $(package.$1),$(error Unknown package '$1'.$(\n)Named in $(or $2,in $$(call _pkg,$1))))

_pkg-all = $(patsubst package.%.dir,%,$(filter package.%.dir,$(.VARIABLES)))

_pkg-imported = $(call Graph_trav,_pkg-deps,$(this-package))
_pkg-deps = $(package.$1.imports)

_pkg-error = $(error Undeclared import:$(\n)$$(package.$1) is used but $1 is not in $$(package.$(this-package).imports))$(\n)))

# Check existence of imported include files
#    make clean, imports, deep, $... => ignore
#    make help => warn
#    other => error
_iiCheck = $(or $(wildcard $1),$(call _iiMissing,$(MAKECMDGOALS),$(_iiMessage)))
_iiMissing = $(if $(filter clean imports deep $$%,$1),,$(if $(filter help,$1),$(info $2),$(error $2)))
_iiMessage = NOT FOUND: $1$(\n)   This is an imported make include file.  Try 'make imports'.

# Convert PACKAGE/path to $(package.PACKAGE)/path
_expand-import-path = $(foreach P,$(word 1,$(subst /, / ,$1)),$(call _pkg,$P,$$(include-imports) entry '$1')$(patsubst $P%,%,$1))

# Assign `package.PKG` for packages, and then include imported makefiles
#   $1 = imports & their descendants.  This means that dependencies
#        can "piggyback"; the important thing is to validate build order.
#   $2 = all packages
_import-packages = \
  $(call _eval,eval-packages,\
    $(foreach P,$1,\
      package.$P := $(patsubst %/,%,$(patsubst %/.,%,$(package.$P.dir)$(value package.$P.outdir)))$(\n))$(\n)\
    $(foreach P,$(filter-out $1,$2),\
      package.$P = $$(call _pkg-error,$P)$(\n))$(\n)\
    include $(foreach P,$(include-imports),$(call _iiCheck,$(call _expand-import-path,$P))))

# Load minion

minion_start = 1
include $(_tt)build/minion.mk
$(call _import-packages,$(_pkg-imported),$(_pkg-all))
$(minion_end)
