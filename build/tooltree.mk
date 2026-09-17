# Project-wide build rules
#
# User makefiles typically include this file after defining all their build
# targets using Minion variables or Make rules.  User makefiles may also
# define properties of Package() Minion instances, and the following:
#
#    $(tooltreeName)
#    $(tooltreeImports)
#    $(tooltreeMakefiles)
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

# By default, cache all rules involved in `make default`.
minionCache ?= default

ifdef tooltreeImports
  tooltreeName ?= root
  Package($(tooltreeName)).imports = $(tooltreeImports)
endif

tooltreeName ?= $(notdir $(abspath .))

# `*` refers to all makefiles exported by imported packages.
tooltreeMakefiles ?= *

# aliases
all ?= Variants(deep)
deep ?= Package($(tooltreeName))
imports ?= Package@_thisImports


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

Package(bench).imports = luau build-lua monoglot lpeg
Package(bench).root = $(_tt)bench/

Package(build).root = $(_tt)build/

Package(build-js).imports = build-lua luau lpeg
Package(build-js).root = $(_tt)build-js/
Package(build-js).result = $(VOUTDIR)exports
Package(build-js).result-makefiles = build-js.mk

Package(build-lua).imports = lua
Package(build-lua).root = $(_tt)build-lua/
Package(build-lua).result = .
Package(build-lua).result-makefiles = build-lua.mk

Package(jsu).root = $(_tt)jsu/
Package(jsu).result = .
Package(jsu).imports = build-js

Package(lpeg).imports = build-lua lua lpegsources
Package(lpeg).root = $(_tt)lpeg/
Package(lpeg).result = $(VOUTDIR)exports
Package(lpeg).result-luaPathDirs = .

Package(lpegsources).root = $(_tt)opensource/lpeg-0.12

Package(lua).imports = luasources
Package(lua).root = $(_tt)lua/
Package(lua).result = $(VOUTDIR)exports

Package(luasources).root = $(_tt)opensource/lua-5.2.3

Package(luau).imports = build-lua lua
Package(luau).root = $(_tt)luau/
Package(luau).result = $(VOUTDIR)exports
Package(luau).result-luaPathDirs = .

Package(mdb).imports = luau build-lua monoglot build-js jsu lpeg
Package(mdb).root = $(_tt)mdb/
Package(mdb).result = $(VOUTDIR)exports

Package(monoglot).imports = luau build-lua lpeg lua
Package(monoglot).root = $(_tt)monoglot/
Package(monoglot).result = $(VOUTDIR)exports
Package(monoglot).result-luaPathDirs = .

Package(pages).imports = smark
Package(pages).root = $(_tt)pages/
Package(pages).result = $(VOUTDIR)

Package(smark).imports = luau build-lua lpeg
Package(smark).root = $(_tt)smark/
Package(smark).result = $(VOUTDIR)exports
Package(smark).result-makefiles = smark.mk

Package(webdemo).imports = luau build-lua lua monoglot lpeg
Package(webdemo).root = $(_tt)webdemo/
Package(webdemo).result = .

#----------------------------------------------------------------
# Tooltree classes
#----------------------------------------------------------------

# Use a simpler {outBasis} than default (no .EXT in .out/Class/... directories)
Builder.outBasis = $(VOUTDIR)$(call _outBasis,$(_class),$(_argText),%,$(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in},in)))),$(_arg1))


# Tooltree C compilation defaults
#
CC.inherit = ttCC CCBase
ttCC.objFlags = $(if {isDebug},{dbgFlags},{optFlags})
ttCC.isDebug = $(call _v,debug)
ttCC.dbgFlags = -D_DEBUG -ggdb
ttCC.optFlags = -O2
ttCC.srcFlags = {warnFlags} -fno-strict-aliasing -fPIC -fstack-protector
ttCC.stdFlags = -std=c99
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


# Package(PACKAGE) : Builder for PACKAGE
#
Package.inherit = _Package
_Package.inherit = _IsPhony Builder
#
# Builder-focused properties
#
_Package.outExt = .out
_Package.inIDs = $(foreach P,{imports},$(_class)($P))
# This is a phony rule (always stale) yet we do output a file when there is a build command
_Package.mkdirs = $(if {result},$(dir {@}))
_Package.command = $(if {result},{makeCommand})
_Package.message = $(if {result},{inherit})
_Package.makeCommand = @( cd {root} && {doBuild} ) > {@} 2>&1 || printf '**FAILED: see {@} for log\nOr: cd {root} && make\n'
_Package.cleanCommand = @$(if {result},cd {root} && {doClean} )
_Package.export = $(call _joinDirs,{root},$(or {result},.))
#
# Package-description properties
#
_Package.imports =
_Package.result =
_Package.result-luaPathDirs =
_Package.result-makefiles =
_Package.doBuild = $(MAKE) V=$V
_Package.doClean = $(MAKE) V=$V clean


#----------------------------------------------------------------
# Tooltree functions
#----------------------------------------------------------------

# $(call _joinDirs,BASE,DIRS) : Combineoe path with zero or more relative paths
_joinDirs = $(patsubst %/.,%,$(subst //,/,$(addprefix $1/,$2)))

# return $1 if variable $1 is defined
_defined = $(if $(filter undefined,$(origin $1)),,$1)

_thisImports = $(call get,imports,Package($(tooltreeName)))

# $(call _getPackageExports,TYPE,PACKAGE-NAMES) : Collect all `result-TYPE`
#    values; each is treated as relative to the export directory.
_getPackageExports = $(foreach p,$2,$(call _joinDirs,$(call get,export,Package($p)),$(call get,result-$1,Package($p))))

_ttLog = $(if $(filter $(minionDebug),$1),$(info $1: $(call _qvn,$2)))
_ttEval = $(call _ttLog,$2,EVAL:$1)$(eval $2)

# Assign `package.PKG` for use by the Makefile
_assignPackageVars = \
  $(call _ttEval,imports,\
    $(foreach P,$(_thisImports),\
      package.$P := $(call get,export,Package($P))$(\n)))

_pkgDeps = $(call get,imports,Package($2))

# $(_validMakefiles) : return a list of makefiles to be included.  Before
#    imported packages have been built, the requested makefiles might not
#    exist, yet we want `clean`, `imports`, and other simple targets that
#    should not need the makefiles to proceed.  For other other targets, we
#    warn or error out:
#
#    clean, imports, ...  => silently exclude absent makefiles
#    help, $...           => warn about missing makefiles
#    (others)             => error
#
# `default` is expanded to $(default), so `default=all` or `default=deep`
# will work.
#
_validMakefiles = $(foreach P,$(_mkRequested),$(call _mkCheck,$P,$(_mkGoals)))
_mkSimple = clean imports deep all Package(%
_mkGoals = $(patsubst default,$(default),$(or $(MAKECMDGOALS),default))
_mkRequested = $(patsubst *,$(call _getPackageExports,makefiles,$(_thisImports)),$(tooltreeMakefiles))
_mkCheck = $(or $(wildcard $1),$(call _mkMissing,$2,$(_mkMessage)))
_mkMissing = $(_mkDisableCache)$(if $(filter $(_mkSimple),$1),,$(if $(filter help $$%,$1),$(info $2),$(error $2)))
_mkMessage = NOT FOUND: $1$(\n)   This is an imported make include file.  Try 'make imports'.
_mkDisableCache = $(call _ttEval,imports,minionCache =)

# Load minion

minionStart = 1
include $(_tt)build/minion.mk

$(_assignPackageVars)
$(call _ttEval,imports,include $(_validMakefiles))

$(minionEnd)
