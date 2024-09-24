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

# Use parallel builds for all projects.  Setting "-jN" in MAKEFLAGS a
# submake triggers "warning: -jN forced in submake" errors.
#
# MAKEFLAGS hides "-j" from us in the top-level make, but -Rr will appear,
# so use "make -R" to avoid parallel builds. (!)
ifeq "$(MAKEFLAGS)" ""
MAKEFLAGS += -j -Rr
endif

#----------------------------------------------------------------
# Variant configuration
#----------------------------------------------------------------

# Default is a single variant.  Use "make V=..." to select a specific variant.
V ?=
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

package.build.dir = $(_tt)build/

package.build-js.dir = $(_tt)build-js/
package.build-js.outdir = $(VOUTDIR)exports
package.build-js.imports = build-lua luau lpeg

package.build-lua.dir = $(_tt)build-lua/
package.build-lua.outdir = .
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
package.pages.imports = build build-js build-lua jsu luau mdb monoglot smark

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
Alias(deep).in = Package($(thisPackage))
Alias(imports).in = Package@package.$(thisPackage).imports

thisPackage ?= $(notdir $(abspath .))

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


# Tooltree C compilation defaults
#
CC.inherit = ttCC CCBase
ttCC.objFlags = $(if {isDebug},{dbgFlags},{optFlags})
ttCC.isDebug = $(_isDebug)
ttCC.dbgFlags = -D_DEBUG -ggdb
ttCC.optFlags = -O2
ttCC.srcFlags = {warnFlags} -std=c99 -fno-strict-aliasing -fPIC -fstack-protector
ttCC.warnFlags = -Werror -Wall -Wextra -pedantic -Wshadow -Wcast-qual\
  -Wcast-align -Wno-unused-parameter -Wstrict-prototypes -Wmissing-prototypes\
  -Wold-style-definition -Wnested-externs -Wbad-function-cast -Winit-self

CC.compiler = clang
CExe.compiler = clang


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
# Process packages
#----------------------------------------------------------------

# Access $(package.NAME) and validate NAME
_pkg = $(or $(package.$1),$(error Unknown package '$1'.$(\n)Named in $(or $2,in $$(call _pkg,$1))))

_pkg-all = $(patsubst package.%.dir,%,$(filter package.%.dir,$(.VARIABLES)))

_pkg-imported = $(call _traverse,_pkg-deps,,$(thisPackage))
_pkg-deps = $(package.$2.imports)

_pkg-error = $(error Undeclared import:$(\n)$$(package.$1) is used but $1 is not in $$(package.$(thisPackage).imports))$(\n)))

# Check existence of imported include files
#    make clean, imports, deep, $... => ignore
#    make help => warn
#    other => error
_iiCheck = $(or $(wildcard $1),$(call _iiMissing,$(MAKECMDGOALS),$(_iiMessage)))
_iiMissing = $(if $(filter clean imports deep $$%,$1),,$(if $(filter help,$1),$(info $2),$(error $2)))
_iiMessage = NOT FOUND: $1$(\n)   This is an imported make include file.  Try 'make imports'.

# Convert PACKAGE/path to $(package.PACKAGE)/path
_expand-import-path = $(foreach P,$(word 1,$(subst /, / ,$1)),$(call _pkg,$P,$$(includeImports) entry '$1')$(patsubst $P%,%,$1))

# Assign `package.PKG` for packages, and then include imported makefiles
#   $1 = imports & their descendants.  This means that dependencies
#        can "piggyback"; the important thing is to validate build order.
#   $2 = all packages
_import-packages = \
  $(foreach P,$1,\
    package.$P := $(patsubst %/,%,$(patsubst %/.,%,$(package.$P.dir)$(value package.$P.outdir)))$(\n))$(\n)\
  $(foreach P,$(filter-out $1,$2),\
    package.$P = $$(call _pkg-error,$P)$(\n))$(\n)\
  include $$(foreach P,$$(includeImports),$$(call _iiCheck,$$(call _expand-import-path,$$P)))

# Load minion

minionStart = 1
include $(_tt)build/minion.mk
$(call _eval,$(call _import-packages,$(_pkg-imported),$(_pkg-all)),eval-packages)
$(minionEnd)
