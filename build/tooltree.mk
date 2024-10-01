# Project-wide build rules

_tt := $(patsubst %build/,%,$(dir $(lastword $(MAKEFILE_LIST))))

#----------------------------------------------------------------
# Variant configuration
#----------------------------------------------------------------

Variants.all = release debug
V(debug).debug = 1

#----------------------------------------------------------------
# Package configuration
#----------------------------------------------------------------
#
# Below are descriptions of the packages known to Tooltree.  Makefiles
# external to tooltree may define their own packages before including
# tooltree.mk.
#
# Packages are described using variables named `package.<NAME>.property`.
# Packages have the following properties:
#
#   dir: the package directory.  This is where its Makefile resides.
#   outdir: a relative path from .dir to the exports directory.
#           If undefined, there is no build step.
#   imports: a list of packages that must be built this package
#
# When the `dir` property is defined for a package, tooltree.mk will compute
# the variable `package.<NAME>`, which describes the location of the exports
# directory for package <NAME>.
#
# If the package does not have a build step, `package.PKG` will be defined
# as DIR (without its trailing "/").

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
package.lpeg.imports = build-lua lua

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



#----------------------------------------------------------------
# Process packages
#----------------------------------------------------------------

_all-packages = $(patsubst package.%.dir,%,$(filter package.%.dir,$(.VARIABLES)))

# Set `package.PKG` for each package defined with `package.PKG.dir`
#
_export-packages = \
  $(foreach P,$(_all-packages),\
    $(eval package.$P := $(patsubst %/,%,$(patsubst %/.,%,$(package.$P.dir)$(value package.$P.outdir))))\
    $(call _log,package.$P,$(package.$P)))

# `include-imports` holds a list of paths to makefiles that are to be
#    included.  The first element in the path is the name of the exporting
#    package, and it will be replaced with that package's export directory.
#    For example, 'p1/defs.mk' expands to `$(package.p1)/defs.mk` which
#    might look something like '../p1/.out/exports/defs.mk.
#
#    These makefiles are included after minion.mk has been loaded because
#    $(package.PKG) variables generally include $(VOUTDIR) or $V which are
#    defined or defaulted by Minion.
#
_do-include-imports = \
   $(call _eval,packageIncludes,\
      include $(foreach P,$(include-imports),$(call _get-import-path,$P)))

_get-import-path = $(call _pkg-export,$(_pathFirst))$(_pathRest)
_pathFirst = $(word 1,$(subst /, / ,$1))
_pathRest = $(patsubst $(_pathFirst)%,%,$1)
_pkg-export = $(or $(package.$1),UNKNOWN_PACKAGE_$1)

# Load minion

minion_start = 1
include $(_tt)build/minion.mk
$(_export-packages)
$(_do-include-imports)
$(minion_end)
