# Project-wide build rules
#
# User makefiles typically include this file after defining all their build
# targets using Minion variables or Make rules.  User makefiles may also
# define the following:
#
#    $(thisPackage)
#    $(includeImports)
#    Package descriptions:
#      $(package.NAME.dir)
#      $(package.NAME.imports)
#      $(package.NAME.outdir)
#
# See tooltree.txt for descriptions of these.
#
_tt := $(patsubst %build/,%,$(dir $(lastword $(MAKEFILE_LIST))))

_uname := $(shell uname)

# Use parallel builds for all projects.  Setting "-jN" in MAKEFLAGS a
# submake triggers "warning: -jN forced in submake" errors.
#
# MAKEFLAGS hides "-j" from us in the top-level make, but -Rr will appear,
# so use "make -R" to avoid parallel builds. (!)
ifeq "$(MAKEFLAGS)" ""
MAKEFLAGS += -j -Rr
endif

#----------------------------------------------------------------
# Variants and variant properties
#----------------------------------------------------------------

# Default is a single variant.  Use "make V=..." to select a specific variant.
V ?=
Variants.all = release debug

V.compiler = gcc
V.debug =
# Fall back to `true` if node is not present; this bypasses unit tests.
# We direct stderr to /dev/null because `which` on Linux is noisy.
V.node := $(notdir $(firstword $(shell which node nodejs 2>/dev/null) true))

# V-FLAG.prop will apply when FLAG appears in $V (dash-delimited).
V-debug.debug = 1
V-llvm.compiler = clang

# Allow local customization in a separate file.  We use $(wildcard ...) here
# because if we pass a non-existent file to `-include` Make will match it
# with the "%:" pattern rule Minion uses when `$(...)` targets are handled.
include $(wildcard $(_tt).tooltree.mk)

# Evaluate property $1 for current variant.
_v = $($(firstword $(foreach v,$(patsubst %,V-%,$(subst -, ,$V)) V,$(call _defined,$v.$1)) _vgetError))
_vgetError = $(error Undefined property: V($V).$1$(\n)$(call _whereAmI,call _v$;$1))


#----------------------------------------------------------------
# Package configuration
#----------------------------------------------------------------
#
# Below are descriptions of the packages known to Tooltree.
#

package.bench.dir = $(_tt)bench/
package.bench.imports = luau build-lua monoglot lpeg

package.build.dir = $(_tt)build/

package.build-js.dir = $(_tt)build-js/
package.build-js.outdir = $(VOUTDIR)exports
package.build-js.imports = build-lua luau lpeg

package.build-lua.dir = $(_tt)build-lua/
package.build-lua.outdir = .
package.build-lua.imports = lua

package.jsu.dir = $(_tt)jsu/
package.jsu.outdir = .
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
package.pages.imports = smark

package.smark.dir = $(_tt)smark/
package.smark.outdir = $(VOUTDIR)exports
package.smark.imports = luau build-lua lpeg

package.webdemo.dir = $(_tt)webdemo/
package.webdemo.outdir = .
package.webdemo.imports = luau build-lua lua monoglot lpeg

#----------------------------------------------------------------
# Tooltree function, class, and alias definitions
#----------------------------------------------------------------

Alias(all).in = Variants(deep)
Alias(deep).in = Package($(thisPackage))
Alias(imports).in = Package@package.$(thisPackage).imports

# return $1 if variable $1 is defined
_defined = $(if $(filter undefined,$(origin $1)),,$1)

# Use a simpler {outBasis} than default (no .EXT in .out/Class/... directories)
Builder.outBasis = $(VOUTDIR)$(call _outBasis,$(_class),$(_argText),%,$(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in},in)))),$(_arg1))


# Tooltree C compilation defaults
#
CC.inherit = ttCC CCBase
ttCC.objFlags = $(if {isDebug},{dbgFlags},{optFlags})
ttCC.isDebug = $(call _v,debug)
ttCC.dbgFlags = -D_DEBUG -ggdb
ttCC.optFlags = -O2
ttCC.srcFlags = {warnFlags} -std=c99 -fno-strict-aliasing -fPIC -fstack-protector
ttCC.warnFlags = -Werror -Wall -Wextra -pedantic -Wshadow -Wcast-qual\
  -Wcast-align -Wno-unused-parameter -Wstrict-prototypes -Wmissing-prototypes\
  -Wold-style-definition -Wnested-externs -Wbad-function-cast -Winit-self
ttCC.compiler = $(call _v,compiler)


CExe.inherit = CExe-$(_uname) _CExe
CExe.compiler = $(call _v,compiler)
CExe-Linux.libFlags = -lm -ldl -Wl,--export-dynamic 


# SharedLib(OBJECTS): Create a shared library
#
SharedLib.inherit = SharedLib-$(_uname) CExe
SharedLib.outExt = .so
SharedLib-Darwin.libFlags = -dynamiclib -undefined dynamic_lookup
SharedLib-Linux.libFlags = -shared -Wl,-unresolved-symbols=ignore-all


# Lib(OBJECTS): Create static library
#
Lib.inherit = Builder
Lib.outExt = .lib
Lib.command = ar -rsc {@} {^}
Lib.inferClasses = CC.c


# CTest(foo.c) infers CExe(foo.c) infers CC(foo.c)
CTest.inherit = Test
CTest.inferClasses = CExe.c


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
_Package.inherit = _IsPhony Builder
_Package.outExt = .out
_Package.inIDs = # no dependencies (for now)
_Package.deps = $(foreach P,{p-imports},$(_class)($P))
# This is a phony rule (always stale) yet we do output a file when there is a build command
_Package.mkdirs = $(if {p-outdir},$(dir {@}))
_Package.command = $(if {p-outdir},{makeCommand})
_Package.message = $(if {p-outdir},{inherit})
_Package.makeCommand = @( cd {p-dir} && $(MAKE) V=$V) > {@} 2>&1 || printf '**FAILED: see {@} for log\nOr: cd {p-dir} && make\n'
_Package.cleanCommand = @$(if {p-outdir},cd {p-dir} && $(MAKE) V=$V clean)

# Package properties
_Package.p-dir = $(package.$(_arg1).dir)
_Package.p-imports = $(package.$(_arg1).imports)
_Package.p-outdir = $(package.$(_arg1).outdir)


#----------------------------------------------------------------
# Import Packages
#----------------------------------------------------------------

thisPackage ?= $(notdir $(abspath .))
includeImports ?=

# Access $(package.NAME) and validate NAME
_pkg = $(or $(package.$1),$(error Unknown package '$1'.$(\n)Named in $(or $2,in $$(call _pkg,$1))))

_allPackages = $(patsubst package.%.dir,%,$(filter package.%.dir,$(.VARIABLES)))

_importedPackages = $(call _traverse,_pkgDeps,,$(thisPackage))
_pkgDeps = $(package.$2.imports)

_pkgError = $(error Undeclared import:$(\n)$$(package.$1) was used but $1 is not in $$(package.$(thisPackage).imports))$(\n)))

# $(includeImports) will fail if imported packages have not been built.  We
# still want `clean`, `imports`, and other simple targets to succeed, and
# they should, so we avoid warnings and errors for them, and disable caching
# (which would probably fail).  For other targets, we warn or error out:
#
#    Ignore: clean, imports, deep, all
#    Warn:   help, $...
#    Error:  (others)
#
_iiDisableCache = $(call _eval,minionCache =,missingImport)
_iiCheck = $(or $(wildcard $1),$(call _iiMissing,$(MAKECMDGOALS),$(_iiMessage)))
_iiMissing = $(_iiDisableCache)$(if $(filter clean imports deep all,$1),,$(if $(filter help $$%,$1),$(info $2),$(error $2)))
_iiMessage = NOT FOUND: $1$(\n)   This is an imported make include file.  Try 'make imports'.

# Convert PACKAGE/path to $(package.PACKAGE)/path
_expandImportPath = $(foreach P,$(word 1,$(subst /, / ,$1)),$(call _pkg,$P,$$(includeImports) entry '$1')$(patsubst $P%,%,$1))

# Assign `package.PKG` for packages, and then include imported makefiles
#   $1 = imports & their descendants.  This means that dependencies
#        can "piggyback"; the important thing is to validate build order.
#   $2 = all packages
_importDefs = \
  $(foreach P,$1,\
    package.$P := $(patsubst %/,%,$(patsubst %/.,%,$(package.$P.dir)$(value package.$P.outdir)))$(\n))\
  $(foreach P,$(filter-out $1,$2),\
    package.$P = $$(call _pkgError,$P)$(\n))

_importPackages = \
  $(call _eval,$(call _importDefs,$(_importedPackages),$(_allPackages)),imports)\
  $(call _eval,include $(foreach P,$(includeImports),$(call _iiCheck,$(call _expandImportPath,$P))),imports)

# Load minion

minionStart = 1
include $(_tt)build/minion.mk
$(_importPackages)
$(minionEnd)
