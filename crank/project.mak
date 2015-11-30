#----------------------------------------------------------------
# project.mak
#----------------------------------------------------------------
define <help>

make TARGET...

    TARGET can be:
       PACKAGE         : build all configured variants of a package
       PACKAGE@VARIANT : build a specific variant of a package

    The package name `all` is a synthetic package that represents the
    entire project. Its dependencies are listed in the `Package` variable
    in the Makefile.

    If no targets are given, `all` is the default.

make graph [ root=TARGET ] [ VAR=VALUE ... ]

    Display dependency tree. This will describe the packages to be built
    when a specified root target is built.  The default root is `all`.

make configure [ VAR=VALUE ... ]

    Generate configuration files. Command line variable assignments may be
    used to modify the configuration; these assignments will remain in effect
    during a later auto-reconfiguration (e.g. when a Package file changes).

make clean
make clean_PACKAGE
make clean_PACKAGE@VARIANT
make clean_configure

    Remove build/configuration results.

make help

    Display this message.

See project.txt for more information.


endef

#----------------------------------------------------------------
# Configuration Defaults


# `Variants` gives the set of variants (of the project) to configure. By
# default, we configure the null variant.
#
# When a project variant is built, all the required package variants will be
# built. Each package may have a different set of variants, as specified by
# the packages that include it.
Variants ?= release


# This directory holds the generated `tree.mak` file, dependency files, and
# log of sub-package build results.
<projectBuildDir> ?= .built


# `@@` controls noisiness
@@ ?= @


include $(dir $(lastword $(MAKEFILE_LIST)))defs.min


#----------------------------------------------------------------
# User settings

# This is a good place to define user- or system-specific variables required
# to build the project (e.g. identify toolchain locations).
userConfigFile := $(firstword $(wildcard $(addsuffix /.userconfig,. .. ../.. ../../..)))

-include $(userConfigFile)


#----------------------------------------------------------------
# Misc. functions

<isVerbose> = $(filter 2,$(crank_DEBUG))

<verbose> = $(if $(<isVerbose>),$(info $1))

<keywords> := include sinclude -include define ifdef ifndef ifeq ifneq else endif export unexport override

<escLHS> = $(if $(filter $1,$(<keywords>)),$$())$1

<set> = $(call <eval>,$(<escLHS>) := $(call <escape>,$2))

<tree.mak> := $(<projectBuildDir>)/tree.mak

<date> := $(shell date)

<do> = $(eval $(value $1))

# encode spaces, tabs, and %
<wenc> = $(or $(subst %,!p,$(subst $(\t),!+,$(subst $(\s),!0,$(subst !,!1,$1)))),!.)

# return true if all words in $1 are equal
<allEQ> = $(if $(filter-out $(word 1,$1),$1),,1)

# Leading spaces are insignificant but unsightly in makefiles, so we strip
# them out.  (Using `foreach` results in extraneous spaces, so we try to leave
# them at the start of a line.)
#
<writeMakefile> = \
  $(if $(<isVerbose>),$(info ----------------> $1$(\n)$2$(\n)<----------------$(\n))) \
  $(shell $(call <writeFile>,$1,$(subst $(\n) ,$(\n),$2))) \
  $(info ==> writing $1)


# extract key or value from "key=value"
<mapKey> = $(patsubst .%,%,$(firstword $(subst =, ,.$1)))
<mapValue> = $(subst $(\s),=,$(wordlist 2,999,$(subst =, ,.$1)))

# If $C is defined, don't invoke p.file which would re-enter variable $(&!)
<errorContext> = $(if $(filter auto%,$(origin p)),Error processing package '$p'$(\n)$(if $C,,$(p.file): ))

# Context variables:
#   $v = current v
#   $p = current package name
#   $d = current deps entry ("name=value")

v = $(call <error>,'v' accessed out of context)
p = $(call <error>,'p' accessed out of context)
d = $(call <error>,'d' accessed out of context)


#------------------------------------------------------------------------
# `Package` class
#

# all packages included
Package := # all packages; initialized when package tree is traversed

# .dir = directory containing the package
Package.dir ?= $I

# .file = the expected name of the package file (if it exists at all).
Package.file ?= $(call .,dir)/Package

Package.rule = $(call .,target): $(call .,prereqs)$(\n)
Package.prereqs = $(call get,target,Build,$(call .,builds))
Package.target = $I
Package.builds = $(foreach v,$(call .,V),$I@$v)

Package.depVars = $(call <uniq>,$(foreach d,$(call get,dmap,Build,$(call .,builds)),$(call <mapKey>,$d)))

# Some variants may have a conf file while others do not. We don't see a
# compelling use case for multiple conf files, but there seems to be no need
# to forbid that.
Package.conf = $(call <uniq>,$(call get,conf,Build,$(call .,builds)))

# The set of V's that requested a conf file.
Package.confVs = $(foreach v,$(Package[$I].V),$(if $(Build[$I@$v].conf),$v))

# rule to run configure command on all variants
Package.configureRule = configure_$I: $(call get,configureTarget,Build,$(call .,builds))$(\n)

#------------------------------------------------------------------------
# `Build` class
#
# Each Built item identifies a specific variant of a package. The item name
# is "<pakageName>@<variantName>". Builds that have dependencies or make
# commands appear as targets in the tree makefile.
#
# The following build properties are initialized with corresponding
# Package properties:
#
#   Build.result
#   Build.make
#   Build.clean
#   Build.conf
#   Build.deps
#   Build.v
#   Build.configure
#
# Additionally:
#
#   Build.dmap = map from variables to build names:  var=pkg@v ...


Build := # all builds; populated when package tree is traversed

Build.pkg = $(word 1,$(subst @, ,$I))
Build.dir = $(call get,dir,Package,$(Build.pkg))
Build.rule = $I: $(call .,prereqs)$(\n)$(call .,commands)$(\n)$(\n)
Build.commands = $(if $(call .,make),$(\t)$$(call _job,$I,$(call .,dir),$(call .,make)))
Build.cleanCommands = $(\n)$(\t)cd $(call .,dir) && $(call .,clean)

# target name (== build name) IFF this build is a makefile target
Build.target = $(if $(or $(call .,dmap),$(call .,make)),$I)

# resultDir = result directory (relative to CWD vs. relative to package dir)
Build.resultDir = $(call get,dir,Package,$(call .,pkg))/$(call .,result)

# builds = other builds upon which this build depends
Build.builds = $(call <uniq>,$(foreach d,$(call .-,dmap),$(call <mapValue>,$d)))

# prereqs = other targets upon which this build depends (builds that are also targets)
Build.prereqs = $(call get,target,Build,$(call .,builds))

# configureTarget = target name for `configure` rule IFF the rule should be generated
Build.configureTarget = $(if $(or $(call .,configure),$(call .,configureDeps)),configure_$I)

# configureDeps = target names of configure rules for child builds
Build.configureDeps = $(strip $(call get,configureTarget,Build,$(call .,builds)))

# configureRule = rule to run `configure` command
Build.configureRule = configure_$I: $(call .,configureDeps)$(\n)$(if $(call .,configure),$(\t)$$(call _job,configure $(call <words>,$I),$(call .,dir),$(call .,configure))$(\n))$(\n)

Build.configureRuleIf = $(if $(call .,configureTarget),$(call .,configureRule))


#------------------------------------------------------------------------
# Shortcuts
#
#    p.xxx   --> function of $p (package name)
#    d.xxx   --> function of $d (dependency entry: var=pkg?v)

p.dir = $(call get,dir,Package,$p)
p.file = $(call get,file,Package,$p)
p.loadPackage = \
  $(call <eval>, \
    $(if $(call <defined>,Package[$p].package),\
      $(value Package[$p].package), \
      -include $(p.file)))

# all variants required for package $p
p.V = $(Package[$p].V)

p.conf = $(call get,conf,Package,$p)
p.confVs = $(call get,confVs,Package,$p)

# $(call p.sameForAllV,VAR) --> true if VAR expands to same value for all the package's V's
p.sameForAllV = $(call <allEQ>,$(foreach v,$(p.confVs),$(call <wenc>,$($1))))

# Normalize dependency entry by supplying defaults:
#
#   [varname=] [pkgname] [?query]
#
#   query defaults to $v.
#   pkgname defaults to $p.
#   varname defautls to pkgname or $p.

dpv.pq   = $(subst ?, ,$(patsubst ?%,$p?%,$(lastword $(subst =, ,$d))))
dpv.pkg  = $(word 1,$(dpv.pq))
dpv.q    = $(or $(word 2,$(dpv.pq)),$v)
dpv.var  = $(if $(findstring =,$d),$(word 1,$(subst =, *anonymous* ,$d)),$(dpv.pkg))
dpv.norm = $(dpv.var)=$(dpv.pkg)?$(dpv.q)

# These operate on normalized dependency entries:  var=pkg?v

d.var = $(word 1,$(subst =, ,$d))
d.build = $(lastword $(subst =, ,$d))
d.pq  = $(subst ?, ,$(lastword $(subst =, ,$d)))
d.pkg = $(word 1,$(d.pq))
d.q   = $(word 2,$(d.pq))


#----------------------------------------------------------------
# Traverse build tree & construct Build[...] and Package[...] entries

# these variables are assigned by Package files:
PkgVars  = deps result make clean conf v configure

# defaults for package variables
PkgVars.result = .
PkgVars.v = $q


# pm.visit! visit the descendants of one build and return the build name: pkg@v
#
# On entry:
#   $p = package name
#   $q = query string
#
# After loading the package file, we can evaluate the global variable `v` to
# determine the variant of the build. This will be overwritten when we
# recurse, so we must use this value before calling `visitDeps`. NOTE: We
# cannot bind `v` dynamically (using `foreach`) because that would mask the
# value of `v` assigned by the Package file.

pv.visit! = \
   $(if $(<debug>),$(info Visiting $p ? $q :)) \
   $(if $(p.dir),,$(call <error>,Could not find package '$p' [listed as a dependency of '$1'])) \
   $(if $(wildcard $(p.dir)/.),,$(call <error>,Directory does not exist: $(p.dir)$(\n) ... Given as location of package '$p' [listed as a dependency of '$1'])) \
   $(foreach f, $(PkgVars), $(call <eval>,$f = $(value PkgVars.$f))) \
   $(if $(filter-out ...,$q),$(p.loadPackage)) \
   $(foreach b, $p@$v, \
      $(if $(filter-out $(Build),$b),\
         $(call <eval>, Build += $b) \
         $(foreach f,$(PkgVars),$(call <set>,Build[$b].$f,$($f))) \
         $(call <eval>, Package := $(Package) $(filter-out $(Package),$p)) \
         $(call <eval>, Package[$p].V := $(p.V) $(filter-out $(p.V),$v)) \
         $(call <eval>, Build[$b].dmap := $(call visitDeps,$(foreach d,$(deps),$(dpv.norm)),$p))) \
      $b)


# Visit all 'deps', returning normalized deps values: variable=package?v
#   $p = including package name
#   $1 = deps
#
visitDeps = \
  $(foreach d,$1,$(foreach p,$(d.pkg),$(foreach q,$(d.q),$(d.var)=$(strip $(call pv.visit!,$2)))))



# Visit all builds in the project, assigning all `Package[name].prop` variables.
#
define <visit>

   # Construct a fake package for the project itself; its "package file"
   # consists only of the 'deps' line.
   Package[all].package := deps = $(value Project)$(\n) v = $$q
   Package[all].file =
   Package[all].dir = .


   # visit all builds of project (and their dependencies, transitively)
   $(if \
     $(foreach p,all,$(foreach q,$(Variants),$(call pv.visit!,all))),)

   allBuilds := $(allBuilds)
endef


#----------------------------------------------------------------
# Display graph of dependencies between nodes

graph.slot = $(filter-out -,$(subst :, ,$(word 1,$1)))
graph.inslot = $(filter $2,$(graph.slot))

# default style (pakman-like)
graph.H = $(subst ., ,.$(if $(graph.inslot),+->,$(if $(graph.slot),|..,...)))
graph.V = $(subst +,|,$(subst -, ,$(subst >, ,$(graph.H))))
graph.EOL =

ifeq ($(graph.style),1)
  # long horizontal dependency lines, under the vertical lines
  graph.H = $(subst .,$(if $4,-, ),..$(if $(graph.inslot),+-,$(if $(graph.slot),|.,..)))
  graph.EOL = >
endif

ifeq ($(graph.style),2)
  # long horizontal dependency lines, over the vertical lines
  graph.H = $(subst .,$(if $4,-, ),..$(if $(graph.inslot),+-,$(if $(graph.slot),$(if $4,-,|).,..)))
  graph.EOL = >
endif


# $(call graph.prefix,SLOTS,NODE,H-OR-V)
graph.prefix = $(if $1,$(graph.$3)$(call graph.prefix,$(<cdr>),$2,$3,$(or $4,$(graph.inslot))))

# $(call graph.deps,NODE,MAP) -> dependencies of node
graph.deps = $(call $2,$1)
graph.pack = $(subst $(\s),:,$1)
graph.unpack = $(subst :, ,$1)

# $(call graph.slots,SLOTS,NEWNODE,MAP) -> new slots list
graph.slots = $(call graph.strim,$(foreach s,$1 $(call graph.pack,$(call graph.deps,$2,$3)),$(or $(call graph.pack,$(filter-out $2,$(call graph.unpack,$s))),-)))
graph.strim = $(if $(filter-out -,$1),$(call <append>,$(<car>),$(call graph.strim,$(<cdr>))))

# $(call graph.lines,NODES,MAP,SLOTS,FORMAT)
#   NODES = nodes to display in graph
#   MAP = function mapping from nodes to their dependencies
#   SLOTS = vertical slots: "-" or colon-delimited unsatisfied deps
#   FORMAT = function for format node ID for printing
graph.lines = $(if $1,$(call graph.prefix,$3,$(<car>),V)$(\n)$(call graph.prefix,$3,$(<car>),H)$(graph.EOL) $(call $4,$(<car>))$(\n)$(call graph.lines,$(<cdr>),$2,$(call graph.slots,$3,$(<car>),$2),$4))

# $(call graph.trav,NODES,GETCHILDREN): Return all descendants of NODES,
# ordered such that each node precedes all its children. (See graph.scm.)
# $(call GETCHILDREN,NODE) should return a list of child nodes.
#
graph.trav = $(if $1,$(call graph.trav,,$2,$3,$(word 1,$1),$(call graph.trav,$(wordlist 2,99999999,$1),$2,$3,,$5)),$(if $(filter $4,$3),CYCLE$(subst $  ,:,$3):$4 $5,$(if $(filter-out $5,$4),$4 $(call graph.trav,$(call $2,$4),$2,$3 $4,,$5),$5)))

graph.cycles = $(foreach c,$(filter CYCLE:%,$1),$(\n)REFERENCE CYCLE : $(subst :, --> ,$(c:CYCLE:%=%)))
graph.text2 = $(call graph.lines,$(filter-out CYCLE:%,$1),$2,,$3)$(graph.cycles)
graph.text = $(call graph.text2,$(call graph.trav,$1,$2),$2,$3)
graph.show = $(info $(graph.text))


#----------------------------------------------------------------

# buildDeps:: target -> dependencies
#   `target` may be a build (package@variant) or a package
buildDeps = $(if $(call <defined>,Package[$1].V),$(call get,builds,Package,$1),$(call get,builds,Build,$1))

# formatDep:: name -> description
formatDep = $(or $(filter $1,$(Build) $(Package)), \
                 $(call <subfilter>,CYCLE:%,% = CIRCULAR REFERENCE!,$1),\
                 $1 : target not in configuration!)

# list of all builds in parents-first order
allBuilds = $(call graph.trav,all,buildDeps)

<graph> = \
   $(call <do>,<visit>)\
   $(call graph.show,$(or $(root),all),buildDeps,formatDep)


DumpBuildProps = deps result make clean conf v dmap pkg dir target resultDir builds prereqs
DumpPackageProps = dir file target V builds prereqs depVars conf confVs

<dump> = \
   $(foreach p,$(Package),\
      $(info $(\n)Package "$p":) \
      $(foreach f,$(DumpPackageProps), \
         $(info $(\s)  $f = $(call get,$f,Package,$p))) \
      $(foreach b,$(call get,builds,Package,$p), \
         $(info $(\n)   Build "$b":) \
         $(foreach f,$(DumpBuildProps), \
            $(info $(\s)     $f = $(call get,$f,Build,$b)))))


#----------------------------------------------------------------
# Construct a configuration file
#
# Conf files define these make variables:
#    V
#    V[...].propName= ...
#    ...dependency vars...
#
# Dependency variables are emitted like this (in the general case):
#
#    dvar[V1] := ...
#    dvar[V2] := ...
#    dvar = $(dvar[$v])
#
# When the value is the same for all variants, we use a simpler form:
#
#    dvar = <path>
#
# The simpler form can be evaluated outside the context of a specific v,
# which is important for make include files.

# Named arguments:
#   $N = name of a dependency variable
#   $F = conf file name (abspath)
#   $p = package
#   $v = variant


# return the result directory for $N
#   Instead of $$(error $N is not defined for variant "$v")), leave the result
#   empty so makefiles can test to see whether a dependency is present.
pvN._rp = $(if $2,$(call <relpath>,$1,$2))
pvN.resultPath = $(call pvN._rp,$(dir $F),$(call get,resultDir,Build,$(call <subfilter>,$N=%,%,$(Build[$p@$v].dmap))))


<vv> = $(sort $(filter-out V.* V.-%,$(filter V.% V[%,$(.VARIABLES))))

# Get list of generic V properties assigned in the Makefile
<Vprops> = $(foreach var,$(filter V.%,$(<vv>)),$(subst $(\s),.,$(call <cdr>,$(subst ., ,$(var)))))

<vprops> = $(patsubst V[$v].%,%,$(filter V[$v].%,$(<vv>)))

p.vprops = $(call <uniq>,$(foreach v,$(p.confVs),$(<vprops>)) $(<Vprops>))

# variant property assignments
pP.vprop = $(if $(call p.sameForAllV,<Pval>),$(pP.vprop1),$(pP.vpropN))
pP.vprop1 = V.$P := $(call <escape>,$(foreach v,$(firstword $(p.confVs)),$(call v.,$P)))$(\n)
pP.vpropN = $(foreach v,$(p.confVs),V[$v].$P := $(call v.,$P)$(\n))
<Pval> = $(call v.,$P)

# dependency variable assignments
pN.dvar = $(if $(call p.sameForAllV,pvN.resultPath),$(pN.dvar1),$(pN.dvarN))
pN.dvar1 = $(call <escLHS>,$N) := $(foreach v,$(firstword $(p.confVs)),$(pvN.resultPath))$(\n)
pN.dvarN = $(call <escLHS>,$N) = $$($N[$$v])$(\n)$(foreach v,$(p.confVs),$N[$v] = $(pvN.resultPath)$(\n))


#................................................................
define pF.confFile
# Auto-generated from ./Package on $(<date>)

$(if $(userConfigFile),include $$(dir $$(lastword $$(MAKEFILE_LIST)))$(call <relpath>,$(dir $F),$(userConfigFile))

)# configured variants

V = $(p.confVs)

# variant properties

$(foreach P,$(p.vprops),$(pP.vprop))

# dependencies

$(foreach N,$(call get,depVars,Package,$p),$(pN.dvar))

endef
#................................................................


#................................................................
define treeMakefile
# tree makefile autogenereated from ../Makefile

export @@ = $(@@)

# $$(call _job,Description,PkgDir,Command)
_log = $(<projectBuildDir>)/$$(subst $$(or ) ,_,$(subst /,_,$$1)).log
_dir = echo "make: Entering directory \`$$(abspath $$2)'"
_cmd = $$(_dir) && cd $$2 && $$3
_msg = echo "... $$(subst @, @ ,$$1)"
_run = ( $$(_cmd) ) > $$(_log) 2>&1 || (cat $$(_log) && false)
_job = $$(@@)$$(_msg) && $$(_run)

# by default, sub-project builds are logged to files and written to stdout only on failure
ifdef NO_LOG
_run = $$(_cmd)
endif

.PHONY: $(call get*,target,Package Build) clean clean_configure

# package rules ==> build all variants

$(call get*,rule,Package)

# variant ("build") rules

$(call get,rule,Build,$(call get*,target,Build))

# configure rules

$(call get,configureRule,Package,all)
$(call get*,configureRuleIf,Build)

# clean the entire tree (top-down order)
clean:$(call get,cleanCommands,Build,$(foreach b,$(allBuilds),$(if $(Build[$b].clean),$b)))

clean_configure:
	$(@@)rm -f $(<configFiles>) $(<tree.mak>)

endef
#................................................................



#----------------------------------------------------------------
# Configuration


<clVars> = $(strip $(foreach X,$(.VARIABLES),$(if $(filter command%,$(origin $X)),$X)))
<varFile> = $(<projectBuildDir>)/vars.min
<packageFiles> = $(wildcard $(call get*,file,Package))

define <varData>
<savedVars> = $(<clVars>)
$(call <for>,X,$(<clVars>),$$X = $$(call <escape>,$$(value $$X))$$(\n))

endef


define <configure>

$(shell mkdir -p $(<projectBuildDir>))

$(if $(<savedVars>),\
    $(info ==> Reconfiguring with old settings:) \
    $(foreach X,$(<savedVars>),$(info ==>   $X = $(value $X))), \
  $(info ==> Configuring...))

# persist command-line-specified vars
$(if $(filter configure,$(MAKECMDGOALS)), \
    $(shell $(call <writeFile>,$(<varFile>),$(<varData>))))

$(call <do>,<visit>)

$(if $(or $(call <defined>,crank_DUMP),$(<debug>)),$(call <dump>))

# write conf files
$(foreach p, $(Package), \
   $(foreach F, $(addprefix $(p.dir)/,$(p.conf)), \
      $(eval <configFiles> += $F) \
      $(call <writeMakefile>,$F,$(pF.confFile))))

# write tree makefile
$(if $(filter CYCLE:%,$(allBuilds)),\
  $(error Cannot construct tree makefile: $(call graph.cycles,$(allBuilds))$(\n)))
$(call <writeMakefile>,$(<tree.mak>),$(call treeMakefile))

# tree makefile dependencies
$(call <writeMakefile>,$(<tree.mak>).d,\
   $(<tree.mak>): $(<packageFiles>)\
   $(foreach c,$(<packageFiles>),$(\n)$c:)$(\n))

# display output directories
$(info ==> Output directories: )
$(foreach b, \
   $(call <uniq>, \
     $(call get,builds,Build, \
        $(call get,builds,Package,all))), \
   $(info ==>   $b  -->  $(call get,resultDir,Build,$b)))

endef

#----------------------------------------------------------------
# Rules
#----------------------------------------------------------------

ifeq "$(filter configure,$(MAKECMDGOALS))" ""
  # include variables specified last time on the command line
  -include $(<varFile>)
endif


ifneq "$(filter $$%,$(MAKECMDGOALS))" ""
  # make '$(expression)' for diagnostics
  $$%: ; @true $(call <show>,$(call if,,,$$$*))
else


phonies    := configure help _stale graph $(customRules)
goals      := $(or $(MAKECMDGOALS),all)
configuring = $(filter configure,$(goals))
treegoals   = $(filter-out $(phonies) $$%,$(goals))

# delegated goals
$(treegoals): $(<tree.mak>)
	@$(MAKE) -f $(<tree.mak>) $@

.PHONY: $(goals) $(phonies)

# tree.mak is built if it doesn't exist, or if 'configure' is a goal
$(<tree.mak>): $(if $(configuring),_stale) $(MAKEFILE_LIST)
	@true $(call <do>,<configure>)

-include $(<tree.mak>).d

# phony targets are always stale
_stale:

configure: $(<tree.mak>) ; @make -f $(<tree.mak>) configure_all

help: ; @true $(info $(<help>))

graph: ; @true $(call <graph>)

endif
