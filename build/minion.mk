# minion.mk

_minionStartVars := $(.VARIABLES)

# User Classes
#
# The following classes may be overridden by user makefiles.  Minion
# attaches no property definitions to them; it just provides a default
# inheritance.  User makefiles may not override other make variables defined
# in this file, except for a few cases where "?=" is used (see below).

Alias.inherit ?= _Alias
Builder.inherit ?= _Builder
CC++.inherit ?= _CC++
CC.inherit ?= _CC
CCBase.inherit ?= _CCBase
CExe++.inherit ?= _CExe++
CExe.inherit ?= _CExe
Clean.inherit ?= _Clean
Copy.inherit ?= _Copy
Exec.inherit ?= _Exec
GZip.inherit ?= _GZip
Graph.inherit ?= _Graph
Link.inherit ?= _Link
Phony.inherit ?= _Phony
Print.inherit ?= _Print
Run.inherit ?= _Run
Test.inherit ?= _Test
Variant.inherit ?= _Variant
Variants.inherit ?= _Variants
Write.inherit ?= _Write


#--------------------------------
# Supported customization variables
#--------------------------------

# V defaults to the first word of Variants.all
V ?= $(word 1,$(Variants.all))

# All Minion build products are placed under this directory
OUTDIR ?= .out/

# Build products for the current V are placed here
VOUTDIR ?= $(OUTDIR)$(if $V,$V/)

minionStart ?=

minionCache ?=
minionNoCache ?=


#--------------------------------
# Built-in Classes
#--------------------------------

# Alias(GOAL) : Generate a phony rule whose {out} matches GOAL,
#     a goal named on the Make command line.  If GOAL is also
#     a Make variable, its value gives the default for {in}.
#     {command} and/or {in} may be overridden by the user makefile.
#
_Alias.inherit = _Goal
_Alias.in = $($(_argText))


# _Clean(INSTANCE) : Clean INSTANCE and its direct & indirect depedencies.
#
_Clean.inherit = _IsPhony Builder
	_Clean.ids = $(filter %$],$(call _expand,$(_args)))
_Clean.in = $(patsubst %,Clean(%),{{ids}.needs})
_Clean.command = $(foreach i,{ids},\
  $(if $(call _hasProperty,cleanCommand,$i),{$i.cleanCommand},rm -f {$i.out}))


# Variants(TARGETS) : Build {all} variants of TARGETS.  Each variant
#    is defined in a separate rule so they can all proceed concurrently.
#
_Variants.inherit = Phony
_Variants.in = $(foreach v,{all},_Variant($(_argText),V:$v))


# Variant(TARGETS,V:VARIANT) : Build VARIANT of TARGETS.
#
_Variant.inherit = Phony
_Variant.command = @$(MAKE) -f $(word 1,$(MAKEFILE_LIST)) --no-print-directory $(foreach t,$(_args),$(call _shellQuote,$t)) V=$(call _shellQuote,$(call _namedArg1,V))


# Phony(PREREQS) : Generate a phony rule.
#
#   A phony rule does not generate an output file.  Therefore, Make cannot
#   determine whether its result is "new" or "old", so it is always
#   considered "old", and its recipe will be executed whenever it is listed
#   as a target.
#
_Phony.inherit = _IsPhony Builder
_Phony.command = @true
_Phony.message =
_Phony.in =


# _IsPhony : Mixin that defines properties as appropriate for all phony
#    targets; can be used to make any class phony.
#
_IsPhony.rule = .PHONY: {@}$(\n){inherit}
_IsPhony.mkdirs = # not a real file => no need to create directory
_IsPhony.vvFile = # always runs => no point in validating
_IsPhony.cleanCommand = # nothing to do


# CCBase(SOURCE) : Base class for invoking a compiler.  This is expected to
#    serve as a template or example for actual projects, which will
#    typically override properties at the CCBase or CC/CC++ level.
#
#    "-MF" is used to generate a make include file that lists all implied
#    depenencies (those that do not appear on the command line -- included
#    headers).
#
_CCBase.inherit = Builder
_CCBase.outExt = .o
_CCBase.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsMF}
_CCBase.depsMF = {outBasis}.d
_CCBase.flags = {stdFlags} {objFlags} {srcFlags} {libFlags} $(addprefix -I,{includes})
_CCBase.stdFlags =
_CCBase.objFlags = -O2
_CCBase.srcFlags = -Wall -Werror
_CCBase.libFlags =
_CCBase.includes =


# CC(SOURCE) : Compile a C file to an object file.
#
_CC.inherit = CCBase
_CC.compiler = gcc
_CC.stdFlags = -std=c99

# CC++(SOURCE) : Compile a C++ file to an object file.
#
_CC++.inherit = CCBase
_CC++.compiler = g++
_CC++.stdFlags = -std=c++20


# Link(INPUTS) : Link an executable or shared library.
#
_Link.inherit = Builder
_Link.outExt =
_Link.command = {compiler} -o {@} {^} {flags}
_Link.flags = {libFlags}
_Link.libFlags =


# CExe(INPUTS) : Link a command-line C program.
#
_CExe.inherit = Link
_CExe.compiler = gcc
_CExe.inferClasses = CC.c


# CExe++(INPUTS) : Link a command-line C++ program.
#
_CExe++.inherit = Link
_CExe++.compiler = g++
_CExe++.inferClasses = CC.c CC++.cpp CC++.cc


# Exec(COMMAND) : Run a command, capturing what it writes to stdout.
#
#    By default, the first ingredient is an executable or shell command, and
#    it is passed as arguments the {execArgs} property and all other
#    ingredients.  Override {exec} to change what is to be executed while
#    retaining other behavior.
#
#    Note: If you override {exec} such that {<} is not the executable, then
#    you should also probably override {inferClasses}.
#
_Exec.inherit = Builder
_Exec.command = ( {exportPrefix} {exec} ) > {@} || ( rm -f {@}; false )
_Exec.exec = {<} {execArgs} $(wordlist 2,9999,{^})
_Exec.execArgs =
_Exec.outExt = .out
# Infer only makes sense for the first item, the one whose type we know.
_Exec.inIDs = $(call _inferIDs,$(word 1,{inX}),{inferClasses}) $(wordlist 2,999999,{inX})
_Exec.inferClasses = CExe.c CExe++.cpp CExe++.cc


# Test(COMMAND) : Run a command (as per Exec) updating an OK file on success.
#
_Test.inherit = Exec
_Test.command = {exportPrefix} {exec}$(\n)touch {@}
_Test.outExt = .ok


# Run(COMMAND) : run command (as per Exec).
#
_Run.inherit = _IsPhony Exec
_Run.command = {exportPrefix} {exec}


# Copy(INPUT)
# Copy(INPUT,out:OUT)
# Copy(INPUT,dir:DIR)
#
#   Copy a single artifact.
#   OUT, when provided, specifies the destination file.
#   DIR, when provided, gives the destination directory.
#   Otherwise, $(VOUTDIR)$(_class) is the destination directory.
#
_Copy.inherit = Builder
_Copy.out = $(or $(call _namedArg1,out),{inherit})
_Copy.outDir = $(or $(call _namedArg1,dir),$(VOUTDIR)$(_class)/)
_Copy.command = cp {<} {@}


# Print(INPUT) : Write artifact to stdout.
#
_Print.inherit = Phony
_Print.in = $(_args)
_Print.command = @cat {<}


# GZip(INPUT) :  Compress an artifact.
#
_GZip.inherit = Exec
_GZip.exec = gzip -c {^}
_GZip.outExt = %.gz


# Write(VAR)
# Write(VAR,out:OUT)
#
#   Write the value of a variable to a file.
#
_Write.inherit = Builder
_Write.out = $(or $(call _namedArg1,out),{inherit})
_Write.command = @$(call _printfCmd,{data}) > {@}
_Write.data = $(or $(call _namedArg1,data),$($(_arg1)))
_Write.in =


# Graph(GOALS) : Draw a graph of dependencies of instances
#
_Graph.inherit = Builder
_Graph.needs =
_Graph.rule = {@}: ; @true $$(info $$(call get,text,$(call _escape,$(_self))))
_Graph.text = $(call _graphDeps,_Graph_getNeeds,{nodeNameFn},{prune},{roots})
_Graph.roots = $(call _Graph_filter,{prune},{inX})
_Graph.prune =
_Graph.nodeNameFn = _Graph_getName

_Graph_filter = $(filter-out $1,$(filter %$],$2))
_Graph_getNeeds = $(call _Graph_filter,$1,$(call get,needs,$2))
_Graph_getName = $(patsubst Alias(%),%,$2)


# Builder(ARGS):  Base class for builders.  See minion.md for details.

# Core builder properties
_Builder.needs = {inIDs} {upIDs} {depsIDs} {ooIDs}
_Builder.out = {outDir}{outName}

define _Builder.rule
{@} : {^} $(call get,out,{upIDs} {depsIDs}) | {{ooIDs}.out}
$(call _recipe,{recipe})
$(patsubst %,-include %
,{depsMF})$(foreach F,{vvFile},_vv =
-include $F
ifneq "$$(_vv)" "{vvValue}"
  {@}: $(_forceTarget)
endif
)
endef

define _Builder.recipe
$(if {message},@echo $(call _shellQuote,{message}))
$(if {mkdirs},@mkdir -p {mkdirs})
$(foreach F,{vvFile},@echo '_vv={vvValue}' > $F)
{command}
endef

# This will be executed by 'Clean(THIS-INSTANCE)' or `make clean THIS-INSTANCE`
_Builder.cleanCommand = rm -f {@} {vvFile} {depsMF}

# If defined, a makefile that holds implicit dependencies (when it exists)
_Builder.depsMF =

# Shorthands
_Builder.@ = {out}
_Builder.< = $(firstword {^})
_Builder.^ = {{inIDs}.out}

# Diagnose someone accidentally using "$@" instead of "{@}".
@ = $(call _badAuto,@,$0)
< = $(call _badAuto,<,$0)
^ = $(call _badAuto,^,$0)

_Builder.in = $(_args)
_Builder.inX = $(call _expand,{in},in)
_Builder.inIDs = $(call _inferIDs,{inX},{inferClasses})

# up: dependencies specified by the class
_Builder.up =
_Builder.upIDs = $(call _expand,{up},up)
_Builder.up^ = {{upIDs}.out}

# oo: order-only dependencies; these may be phony targets, so we allow aliases
_Builder.oo =
_Builder.ooIDs = $(call _expand,{oo},oo)

# deps: direct dependencies not covered by {in} or {up}
_Builder.deps =
_Builder.depsIDs = $(call _expand,{deps},deps)
_Builder.deps^ = {{depsIDs}.out}

# inferClasses: a list of CLASS.EXT patterns
_Builder.inferClasses =

_Builder.outExt = %
_Builder.outDir = $(dir {outBasis})
_Builder.outName = $(foreach e,$(notdir {outBasis}),$(basename $e)$(subst %,$(suffix $e),{outExt}))
_Builder.outBasis = $(VOUTDIR)$(call _outBasis,$(_class),$(_argText),{outExt},$(call get,out,$(filter $(_arg1),$(word 1,{inX}))),$(_arg1))

# message to be displayed when the command executes (if non-empty)
_Builder.message ?= \#-> $(_self)

# directories to be created prior to commands in recipe
_Builder.mkdirs = $(sort $(dir {@} {vvFile}))

# This may be prepended to individual command lines to export environment variables
# listed in {exports}
_Builder.exportPrefix = $(foreach v,{exports},$v=$(call _shellQuote,{$v}) )
_Builder.exports =

# Validity values
_Builder.vvFile ?= {outBasis}.vv
# Use $(basename {@}) to match most of {@} and also {depsMF} as defined for CCBase
_Builder.vvValue = $(call _vvEnc,{command},$(basename {@}))


#--------------------------------
# Minion internal classes
#--------------------------------


# _File(FILENAME) : Do nothing, and treat FILENAME as the output.  This class
#    is used by `get` so that plain file names can be supplied instead of
#    instance names.  Property evaluation logic short-cuts the handling of
#    File instances, so inheritance is not available.
#
_File.out = $(_self)
_File.rule =
_File.needs =


# _Goal(GOAL) : Do nothing.
#
#     Instances of _Goal are phony targets whose {out} matches GOAL,
#     presumably a goal named on the Make command line.
#
_Goal.inherit = Phony
_Goal.out = $(subst :,\:,$(_argText))


# _BuildGoal(GOAL) : Build GOAL.
#
_BuildGoal.inherit = _Goal
_BuildGoal.in = $(_argText)


# _HelpGoal(GOAL) : Invoke `_help!` on GOAL.
#
_HelpGoal.inherit = _Goal
_HelpGoal.command = @true$(call _lazy,$$(call _help!,$(call _escape,$(_argText))))


# _CleanGoal(GOAL) : Clean GOAL.
#
_CleanGoal.inherit = _Goal
_CleanGoal.inIDs = Clean($(_argText))


#--------------------------------
# Internal function and variable definitions
#--------------------------------

# External changes to these variables do not threaten consistency.  V is in
# the cache file name; the cache file itself detects changes to the others.
_cacheOKVars ?= V minionCache minionNoCache
_cacheName ?= $(VOUTDIR)cache.mk
# write out this many rules per printf command line
_cacheGroupSize ?= 40

# Character constants

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
\e := 
[ := (
] := )
; := ,
\q = "#"
define \n


endef


# Is $1 a "safe" arg to "rm -rf"?  (Catch accidental ".", "..", "/" etc.)
_safeToClean = $(if $(filter-out . ..,$(subst /, ,$1)),$1)

define _helpMessage
Minion v1.1 usage:

   make                     Build the target named "default"
   make GOALS...            Build the named goals
   make help                Show this message
   make help GOALS...       Describe the named goals
   make help CLASS          Describe CLASS
   make clean               `$(call get,command,Alias(clean))`
   make clean GOALS...      Remove output files of specified goals
   make graph               Show graph of dependencies for "default"

Goals can be ordinary Make targets, Minion aliases, instances (`Class(Arg)`),
variable indirections (`@var`), or instance properties (`Class(arg).x`). Note
that instances must be quoted for the shell.

endef


#--------------------------------
# Rules
#--------------------------------

clean ?=
Alias(clean).command ?= $(if $(call _safeToClean,$(VOUTDIR)),rm -rf $(VOUTDIR),@echo '** make clean is disabled; VOUTDIR is unsafe: "$(VOUTDIR)"' ; false)

graph ?= 
Alias(graph).in ?= Graph(default)

help ?=
Alias(help).command ?= @true$(call _lazy,$$(info $$(_helpMessage)))

# Alas, this won't work if a goal is defined by the makefile or named on the command line.
_error_default: ; $(error Makefile used minionStart but did not call `$$(minionEnd)`)

.SUFFIXES:
_forceTarget := $(OUTDIR)FORCE
$(_forceTarget):

define _epilogue
  # instrument functions before calling any of them
  $(call _trace,$(minionTrace))

  # Flag some potential OUTDIR misconfigurations that could be costly
  ifneq "/" "$(patsubst %/,/,$(OUTDIR))"
    $(error OUTDIR must end in "/")
  endif

  ifndef MAKECMDGOALS
    .DEFAULT_GOAL = default
  endif

  __modeKey := $(word 1,$(MAKECMDGOALS))
  __modeArgs := $(wordlist 2,999999,$(MAKECMDGOALS))

  ifneq "" "$(filter $$%,$(MAKECMDGOALS))"
    # Expression mode expects a Make expression that may have embedded
    # spaces.  MAKECMDGOALS may not reflect the actual arguments.
    $$%: ; @#$(info $$$* = $(call _qv,$(call or,$$$*)))
    %: ; @echo '... ignoring target "$*" alongside $$(...)' && false
  else ifneq "" "$(and $(filter clean help,$(__modeKey)),$(__modeArgs))"
    # help or clean mode
    ifeq "help" "$(__modeKey)"
       _error = $(info $(subst $(\n),$(\n)   ,ERROR: $1)$(\n))
       _goalIDs := $(patsubst %,_HelpGoal(%),$(__modeArgs)) \
          $(if $(filter-out help,$(__modeArgs)),_Goal(help))
    else
       _goalIDs := _Goal(clean) $(patsubst %,_CleanGoal(%),$(__modeArgs))
    endif
  else
    # build mode
    _goalIDs := $(foreach g,$(or $(MAKECMDGOALS),default),$(call _buildGoalID,$g))
  endif

  ifndef minionCache
    # No caching selected by Makefile
  else ifeq "" "$(strip $(call get,needs,$(filter-out _CleanGoal$[%,$(_goalIDs))))"
    # Bypass cache: Trivial goals do not benefit, and importantly, we avoid
    # the cache when handling `help` (goals may conflict with cached rules,
    # because they take on a new meaning) or `clean` (so we can recover from
    # a corrupted cache file).
  else ifneq "" "$(filter c%,$(foreach v,$(filter-out $(_cacheOKVars),$(_minionStartVars)),$(origin $v)))"
    # Bypass cache: a command-line override was used
  else
    # Use a rule cache file. Recipe expansion is costly, so defer it to rule
    # processing time, only when-and-if the cache needs to be built.
    $(_cacheName): $(MAKEFILE_LIST) ; $(call _rulecacheRecipe,$@)
    -include $(_cacheName)
    # The following line only has an effect when the rule cache does not
    # exist yet.  In that case, it avoids rule generation, because we know
    # Make will immediately restart, and that would be wasted work.
    _cachedIDs ?= %
  endif

  $(call _evalRules,$(_goalIDs),$(_cachedIDs))
endef


# SCAM source exports:
. = $(if $(filter s%,$(flavor ~$(_self).$1)),$(value ~$(_self).$1),$(call _set,~$(_self).$1,$(if $(findstring s,$(flavor $(_self).$1)),$(foreach 0,&$(_self).$1,$(call or,$(call _cx,$1,$(_self)))),$(call $(if $(filter r%,$(flavor &$(_class).$1)),&$(_class).$1,$(call _fset,&$(_class).$1,$(call _cx,$1,$(or $(call _walk,$1,$(_class)),$(call _E1,$1,$2,)))))))))
_? = $(_traceIn)$(call _traceOut,_? '$1',$(call $1,$2,$3,$4,$5,$6,$7,$8))
_E0 = $(call _error,minion: Mal-formed instance name '$(_self)'$(\n)$(if $(filter $[%,$(_self)),No CLASS before '$[',$(if $(findstring $[,$(_self)),No '$]' at end,Unbalanced '$]'))$(\n)$(\n))
_E1 = $(call _error,minion: Undefined property {$1}$(\n)on instance: $(_self)$(\n)$(if $3,via {inherit$(if $(findstring .$1=,$3=),, $1)} in:,$(if $2,during call to:))$(\n)$(\n)$(if $(or $3,$2),$(call _describeVar,$(if $3,$3,$(if $(filter &%,$2),$(word 1,$(call _walk,$(lastword $(subst .,. ,$2)),$(patsubst &%,%,$(word 1,$(subst ., .,$2))))).$(lastword $(subst .,. ,$2)),$2)),   ))$(\n)$(if $(filter u%,$(flavor $(_class).inherit)),$(\n) NOTE: $(_class).inherit is not defined!$(\n))$(\n))
_EI = $(call _error,minion: Invalid target: '$1'$(\n)$(if $(filter %@,$1),Name ends in '@',References undefined variable '$(_ivar)')$(if $2,$(\n)Found while expanding $(if $(filter _BuildGoal$[%,$2),command line goal,$2))$(\n)$(\n))
_arg1 = $(word 1,$(_args))
_argError = $(call _error,minion: Argument '$(subst `,,$1)' is mal-formed:$(\n)   $(subst `,,$(subst `$], *$]* ,$(subst `$[, *$[*,$1)))$(\n)$(if $(C),during evaluation of $(C)($(A)))$(\n)$(\n))
_argGroup = $(if $(findstring `$[,$(subst $],$[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) `$],$]` ,$(patsubst `$[%,`$[% ,$(subst `$], `$],$(subst `$[, `$[,$1)))),$(if $(filter %`,$w),$(subst `,,$w),$w))),$1)),$1)
_argHash = $(if $(or $(findstring $[,$1),$(findstring $],$1),$(findstring :,$1)),$(or $(value *h$1),$(call _set,*h$1,$(_argHash2))),:$(subst $;, :,$1))
_argHash2 = $(subst `,,$(foreach w,$(subst $(if ,,`,), ,$(call _argGroup,$(subst :,`:,$(subst $;,$(if ,,`,),$(subst $],`$],$(subst $[,`$[,$1)))))),$(if $(findstring `:,$w),,:)$w))
_argText = $(patsubst $(_class)(%),%,$(_self))
_args = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))))
_badAuto = $(call _error,minion: Unsafe expansion$(\n)$$$$$1 was evaluated prior to rule processing$(\n)during evaluation of $(if $(filter &%,$2),$(word 1,$(patsubst &%,%,$2)),$$(call $2,...))$(if $(_self), in context of $(_self)))
_buildGoalID = $(if $(or $(_isInstance),$(_isIndirect)),_BuildGoal($1),$(if $(if $(findstring $].,$1),$(filter-out . %$],$(subst $],$] ,$1))),_HelpGoal($1),$(_isAlias)))
_chain = $(if $1,$(call _chain,$(_chp+),$2 $(word 1,$1)),$(filter %,$2))
_checkValue = $(\n)ifneq "$(call _qesc,$2)" "$3"$(\n)  $$(info minion: $$$3 has changed!)$(\n)  $1: $$(_forceTarget)$(\n)endif$(\n)
_chp+ = $(if $(findstring $[,$1),$(filter-out |%,$(subst $[, |,$1)),$(filter-out =%,$($(word 1,$1).inherit) =$1))
_cx = $(foreach w,$(word 1,$2).$1,$(if $(filter s%,$(flavor $w)),$(subst $$,$$$$,$(value $w)),$(if $(findstring {,$(subst },{,$(value $w))),$(call _cxb1,$(value $w),$1,$2,$w),$(value $w))))
_cxD = $(subst $(\t),!+,$(subst $(\s),!0,$(subst !,!1,$1)))
_cxInherit = $(call _cxMemo,$1,$(or $(call _walk,$1,$(call _chp+,$2)),$(call _E1,$1,,$3)))
_cxMemo = $(if $(filter r%,$(flavor &$2.$1)),&$2.$1,$(call _fset,&$2.$1,$(call _cx,$1,$2)))
_cxNest = $(if $(findstring !@,$1),$(subst $(if ,,!@,),$$;,$(call _cxNest2,$(subst !@$],!@$] ,$(subst !@$[, !@$[,$1)))),$1)
_cxNest2 = $(if $(filter !@(%!@),$1),$(call _cxNest2,$(subst !@$],!@$] ,$(subst !@$[, !@$[,$(subst $(\s),,$(foreach w,$1,$(if $(filter !@(%!@),$w), $(subst !@,,$w) ,$w)))))),$(if $(findstring !@$[,$(subst !@$],!@$[,$1)),,$(word 1,$1)))
_cxU = $(subst !1,!,$(subst !0, ,$(subst !+,	,$1)))
_cxb1 = $(call _cxU,$(subst !@,,$(subst $(\s),,$(call _cxb2,$(patsubst !@{%!@},$$(call!0.,%,$$0),$(subst !@{inherit!,!@{inherit !,$(subst $(\s)!@},!@} ,$(subst !, !,$(subst !@{!@},$$(_self),$(subst !0!@},!0},$(subst !@{!0,{!0,$(subst $$!@},},$(subst $$!@{,{,$(subst $$$$,$$$$ ,$(subst },!@},$(subst {,!@{,$(subst $],!@$],$(subst $[,!@$[,$(subst $;,$(if ,,!@,),$(subst .,!@.,$(_cxD))))))))))))))))),$2,$3,$4))))
_cxb2 = $(if $(findstring !@{,$(subst !@},!@{,$1)),$(call _cxb3,$(foreach w,$(subst !@},!@} ,$(subst !@{, !@{,$(subst $(\s),,$1))),$(if $(filter !@{inherit!@} !@{inherit!0%!@},$w),$$(call!0$(call _cxD,$(call _cxInherit,$(if $(filter !@{inherit!@},$w),$(call _cxD,$2),$(if $(findstring !,$(or $(patsubst !@{inherit!0%!@},%,$w),!)),$(call _cxbError,IN,$w,$4,$2),$(patsubst !@{inherit!0%!@},%,$w))),$3,$4))),$w)),$2,$3,$4),$1)
_cxb3 = $(if $(filter !@{%!@},$1),$(call _cxb3,$(subst !@},!@} ,$(subst !@{, !@{,$(subst $(\s),,$(foreach w,$1,$(or $(filter-out !@{%!@},$w),$(foreach x,$(or $(call _cxNest,$(patsubst !@{%!@},%,$w)),$(call _cxbError,UP,$w,$4,$2)),$(if $(findstring !@.,$x),$(if $(filter !@.% %!@.,$x),$(call _cxbError,G1,$w,$4,$2),$(if $(word 3,$(subst !@.,. .,$x)),$(call _cxbError,G2,$w,$4,$2),$$(call!0get,$(word 2,$(subst !@., ,$x)),$(word 1,$(subst !@., ,$x))))),$$(call!0.,$x,$$0)))))))),$2,$3,$4),$(if $(findstring !@{,$(subst !@},!@{,$1)),$(call _cxbError,UB,$(_cxbUB),$4,$2),$1))
_cxbError = $(call _error,minion: Error in property definition$(\n)$(subst @,$(call _cxU,$(subst !@,,$(subst $(\s),,$2))),$(call _cxU,$(patsubst $1!=%,%,$(filter $1%,UP!=Unbalanced!0parentheses!0within!0{...} UB!=Unbalanced!0"{"!0or!0"}"!0in!0definition G1!=Empty!0ID!0or!0PROP!0in!0{ID.PROP} G2!=Too!0many!0"."!0characters!0in!0{ID.PROP} IN!=Unexpected!0characters!0in!0{inherit...}))))$(\n)$(\n)   in: $3 = $(value $3)$(\n)$(if $(findstring $(call _cxU,$(subst !@,,$(subst $(\s),,$2))),$(value $3)),   at: $(call _cxU,$(subst !@,,$(subst $(\s),,$2)))$(\n))$(\n)when evaluating: $(_self).$4$(\n)$(\n))
_cxbUB = $(firstword $(filter !@{% %!@},$(subst !@},!@} ,$(subst !@{, !@{,$1))))
_describeProp = $(if $1,$(if $(filter u%,$(flavor $(word 1,$1).$2)),$(call _describeProp,$(_chp+),$2),$(call _describeVar,$(word 1,$1).$2,   )$(\n)$(if $(and $(filter r%,$(flavor $(word 1,$1).$2)),$(findstring {inherit},$(value $(word 1,$1).$2))),$(\n)...wherein {inherit} references:$(\n)$(\n)$(call _describeProp,$(_chp+),$2))),   <missing definition!>$(\n))
_describeVar = $2$(if $(filter r%,$(flavor $1)),$(if $(findstring $(\n),$(value $1)),$(subst $(\n),$(\n)$2,define $1$(\n)$(value $1)$(\n)endef),$1 = $(value $1)),$1 := $(subst $(\n),$$(\n),$(subst $$,$$$$,$(value $1))))
_eq? = $(findstring $(subst $20,1,$10),1)
_error = $(error $1)
_escape = $(subst $;,$$;,$(subst $[,$$[,$(subst $],$$],$(subst $$,$$$$,$1))))
_eval = $(eval $1)
_evalRules = $(foreach w,$(call _rollupEx,$(sort $(_isInstance)),$2),$(call _eval,$(call get,rule,$w),$w))
_expand = $(call _expandX,$1,$(_self).$2)
_expandX = $(foreach w,$1,$(or $(filter %$],$w),$(if $(findstring @,$w),$(foreach x,$(or $(call _ivar,$w),=@),$(patsubst %,$(if $(filter @%,$w),%,$(subst $(\s),,$(filter %( %% ),$(subst @,$[ ,$w) % $(subst @, $] ,$w)))),$(if $(findstring *,$x),$(call _wildcard,$x),$(if $(filter u%,$(flavor $x)),$(call _EI,$w,$2),$(call _expandX,$($x),$x))))),$(or $(if $(filter f% o%,$(origin $w)),Alias($w)),$w))))
_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),none)
_fsenc = $(subst },@R,$(subst {,@L,$(subst >,@r,$(subst <,@l,$(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst :,@C,$(subst *,@S,$(subst $],@-,$(subst $[,@+,$(subst |,@1,$(subst @,@_,$1)))))))))))))
_fset = $(eval $$1 = $(if $(filter 1,$(word 1,1$20)),$$(or ))$(subst \#,$$(\H),$(subst $(\n),$$(\n),$2)))$1
_fswap = $(if $(_fset),)$3
_graph = $(if $4,$(call _graph,$1,$2,$3,$(wordlist 2,99999999,$4),$(subst ``,` ,$(filter-out %9,$(subst `  ,``,$(patsubst `,` ,$(subst `$(word 1,$4)`,`,$5) `$(subst $(\s),,$(addsuffix `,$(call $1,$3,$(word 1,$4)))) 9)))),$6$(foreach w,$5,$(if $(filter `,$w), ,|)  )$(\n)$(foreach w,$5,$(if $(findstring `$(word 1,$4)`,$w),+->,$(if $(filter `,$w), ,|)  ))$(if $5, )$(call $2,$3,$(word 1,$4))$(\n)),$6)
_graphDeps = $(call _graph,$1,$2,$3,$(call _traverse,$1,$3,$4))
_group = $(if $1,$(subst | ,|0,$(subst ||,,$(join $(subst |,|1,$1),$(subst $(patsubst %,|,$(wordlist 1,$2,$1)),$(patsubst %,|,$(wordlist 1,$2,$1))|,$(patsubst %,|,$1))) )))
_hasProperty = $(if $(strip $(foreach w,$(call _chain,$2),$(findstring s,$(flavor $w.$1)))),1)
_hashGet = $(patsubst $2:%,%,$(filter $2:%,$1))
_help! = $(info $(call _helpOn$(_helpType),$1))
_helpCC = $(call _chp+,$2)
_helpCN = $2
_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(filter-out $(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))
_helpOnAlias = "$1" is an alias for $(_isAlias).$(\n)$(\n)It is defined by:$(\n)   $(call _describeVar,$1)$(\n)$(\n)$(call _helpDeps,$(_isAlias))$(\n)$(\n)It generates the following rule: $(call _qvn,$(call get,rule,$(_isAlias)))
_helpOnClass = Class $1 inherits from these other classes:$(\n)$(\n)$(call _graphDeps,_helpCC,_helpCN,,$1)
_helpOnIndirect = "$1" is an indirection on the following $(if $(findstring *,$(_ivar)),wildcard:$(\n)$(\n)   $(_ivar),variable:$(\n)$(\n)   $(call _describeVar,$(_ivar)))$(\n)$(\n)It expands to the following targets: $(call _fmtList,$(call _expand,$1))$(\n)
_helpOnInstance = $1 is an instance.$(\n)$(\n){out} = $(call get,out,$1)$(\n)$(\n)$(if $(call _hasProperty,command,$1),Command: $(call _qvn,$(subst $(\e),$$,$(subst $$,$$$$,$(call get,command,$1)))),{rule} = $(call _qvn,$(call get,rule,$1)))$(\n)$(\n)$(call _helpDeps,$1)$(\n)
_helpOnInvalidClass = "$1" looks like an instance with an invalid class name;$(\n)`$$$(filter-out |% %$],$(subst $[, |,$(filter %$],$1))).inherit` is not defined.  Perhaps a typo?$(\n)
_helpOnOther = Target $1 is not generated by Minion.  It may be a source$(\n)file or a target defined by a rule in the Makefile.
_helpOnProperty = $(foreach w,$(patsubst .%,%,$(if $(findstring $].,$1),$(filter-out . %$],$(subst $],$] ,$1)))),$(foreach x,$(patsubst %.$w,%,$1),$(if $(call _info,$x inherits from: $(call _chain,$(filter-out |% %$],$(subst $[, |,$(filter %$],$x))))$(\n)$(\n){$w} $(if $(call _hasProperty,$w,$x),is defined by:$(\n)$(\n)$(call _describeProp,$x,$w),is not defined!)),)$(if $(if $(call _fswap,_error,$(call _fswap,_error,$$(call _set,*err*,$$(or $$1,-)),$(value _error)),$(call get,$w,$x)),)$(*err*),Its evaluation results in an error:$(\n)$(*err*),Its value is: $(call _qv,$(call get,$w,$x)))$(\n)$(\n)))
_helpType = $(if $(if $(findstring $].,$1),$(filter-out . %$],$(subst $],$] ,$1))),Property,$(if $(_isInstance),$(if $(filter u%,$(flavor $(filter-out |% %$],$(subst $[, |,$(filter %$],$1))).inherit)),InvalidClass,Instance),$(if $(_isIndirect),Indirect,$(if $(_isAlias),Alias,$(if $(findstring s,$(flavor $1.inherit)),Class,Other)))))
_inferIDs = $(if $2,$(foreach w,$1,$(or $(filter %$],$(patsubst %$(or $(suffix $(if $(filter %$],$w),$(call get,out,$w),$w)),.),%($w),$2)),$w)),$1)
_info = $(info $1)
_isAlias = $(if $(filter f% o%,$(origin $1)),Alias($1))
_isIndirect = $(if $(findstring @,$1),$(filter-out %$],$1))
_isInstance = $(filter %$],$1)
_ivar = $(filter-out %@,$(subst @,@ ,$1))
_lazy = $(subst $$,$(\e),$1)
_namedArg1 = $(word 1,$(_namedArgs))
_namedArgs = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))),$1)
_outBS = $(_fsenc)$(if $(findstring %,$3),,$(suffix $4))$(if $4,$(patsubst _/$(VOUTDIR)%,_%,$(if $(filter %$],$2),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,/$4))))))),$(call _outBX,$2))
_outBX = $(subst @D,/,$(subst $(\s),,$(patsubst /%@_,_%@,$(addprefix /,$(subst @_,@_ ,$(_fsenc))))))
_outBasis = $(if $(filter $5,$2),$(_outBS),$(call _outBS,$1$(subst _$(or $5,|),_|,_$2),$(or $5,out),$3,$4))
_printfCmd = printf "%b" $(call _shellQuote,$(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1))))
_qesc = $(subst $(\n),$$($(\n)),$(subst \#,$$(\H),$(subst ",$$(\q),$(subst $$,$$$$,$1))))
_qv = $(call _qvn,$1,')
_qvn = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)$3  | ,$(\n)$1),$2$1$2)
_rcr2 = @mkdir -p $(dir $1)$(\n)@> $1_tmp_$(\n)$(foreach w,$(call _group,$(filter-out $3,$2),$4),@$(call _printfCmd,$(foreach x,$(call _ungroup,$w),$(\n)$(call get,rule,$x)$(if $3,$(\n)*D-$x = $(filter $3,$(call _rollupOne,$x)))$(\n))) >> $1_tmp_$(\n))@$(call _printfCmd,$(subst endif$(\n)$(\n)if,else if,$(subst $(\n) $(\n),$(\n)$(\n),_cachedIDs = $(filter-out $3,$2)$(\n)$(foreach w,minionCache minionNoCache $('varLog),$(call _checkValue,$1,$($w),$$($w)))$(if $('globLog),$(call _checkValue,$1,$(wildcard $('globLog)),$$(wildcard $('globLog))))$(foreach w,$('shellLog),$(call _checkValue,$1,$(shell $(subst !1,!,$(subst !+,	,$(subst !0, ,$w)))),$$(shell $(subst !1,!,$(subst !+,	,$(subst !0, ,$w))))))))) >> $1_tmp_$(\n)@mv $1_tmp_ $1$(\n)
_recipe = $(subst $(\e),$$,$(subst $$,$$$$,$(subst $(\t)$(\n),,$(subst $(\n),$(\n)	,	$1)$(\n))))
_relpath = $(if $(filter /%,$2),$2,$(if $(filter ..,$(subst /, ,$1)),$(error _relpath: '..' in $1),$(or $(foreach w,$(filter %/%,$(word 1,$(subst /,/% ,$1))),$(call _relpath,$(patsubst $w,%,$1),$(if $(filter $w,$2),$(patsubst $w,%,$2),../$2))),$2)))
_rollup = $(sort $(foreach w,$(filter %$],$1),$w $(call _rollupOne,$w)))
_rollupEx = $(if $1,$(call _rollupEx,$(filter-out $3 $1,$(sort $(filter %$],$(call get,needs,$(filter-out $2,$1))) $(foreach w,$(filter $2,$1),$(value *D-$w)))),$2,$3 $1),$(filter-out $2,$3))
_rollupOne = $(or $(value *n$1),$(call _set,*n$1,$(or $(sort $(foreach w,$(filter %$],$(call get,needs,$1)),$w $(call _rollupOne,$w))),$(if ,, ))))
_rulecacheRecipe = $(info minion: Updating rule cache...)$(call _rcr2,$1,$(call _rollup,$(call _varToIDs,minionCache)),$(filter %$],$(call _varToIDs,minionNoCache)),$(_cacheGroupSize))
_set = $(eval $$1 := $$2)$2
_shell = $(if $(call _set,'shellLog,$(sort $('shellLog) $(subst $(\s),!0,$(subst $(\t),!+,$(subst !,!1,$1))))),)$(shell $1)
_shellQuote = '$(subst ','\'',$1)'
_ti = $(subst .,  ,$(*traceLevel*))
_ti+ = $(eval *traceLevel* := .$(*traceLevel*))
_ti- = $(eval *traceLevel* := $(patsubst %.,%,$(*traceLevel*)))
_tqv = $(call _qvn,$1,',$(_ti))
_trace = $(foreach w,$1,$(call _info,_trace: $(if $(filter u%,$(flavor $w)),function $w not defined!,$(if $(findstring s,$(flavor TRACE*$w)),already traced $w,$(if $(filter $w,_traceIn _traceOut _tqv _qv _qvn _ti+ _ti- _ti),CANNOT trace $w,$(if $(call _fset,TRACE*$w,$(value $w)),)$(if $(call _fset,$w,$$(_traceIn)$$(call _traceOut,$$0,$$(call TRACE*$w,$$1,$$2,$$3,$$4,$$5,$$6,$$7,$$8,$$9))),)tracing $w ...)))))
_traceIn = $(foreach w,$(or $(lastword $(foreach w,1 2 3 4 5 6 7 8 9,$(if $(value $w),$w))),0),$(if $(call _info,$(_ti)($(0)$(if $(filter 0,$w),, )$(foreach x,$(wordlist 1,$w,1 2 3 4 5 6 7 8 9),$(if $(findstring $(\n),$(value $x)),$$$x,'$(value $x)'))) ->),)$(if $(_ti+),)$(if $(foreach x,$(wordlist 1,$w,1 2 3 4 5 6 7 8 9),$(if $(findstring $(\n),$(value $x)),$(call _info,$(_ti)$$$x:$(call _tqv,$(value $x))))),))
_traceOut = $(if $(_ti-),)$(if $(call _info,$(_ti)($1) <- $(call _tqv,$2)),)$2
_traverse = $(if $(word 1,$3),$(call _traverse,$1,$2,$(call $1,$2,$(word 1,$3)) $(wordlist 2,99999999,$3),$(filter-out $(word 1,$3),$4) $(word 1,$3)),$4)
_ungroup = $(subst |1,|,$(subst |0, ,$1))
_uniq2 = $(if $1,$(word 1,$1)   $(call _uniq2,$(filter-out $(word 1,$1),$1)))
_unique = $(filter %,$(subst ^c,^,$(subst ^p,%,$(call _uniq2,$(subst %,^p,$(subst ^,^c,$1))))))
_var = $(if $(call _set,'varLog,$(sort $('varLog) $1)),)$($1)
_varToIDs = $(foreach w,$(call _expand,$($1)),$(if $(filter %$],$w),$w,$(error $1 references unknown target '$w')))
_vvEnc = .$(subst ',`,$(subst ",!`,$(subst `,!b,$(subst $$,!S,$(subst $(\n),!n,$(subst $(\t),!+,$(subst \#,!H,$(subst $2,!@,$(subst \,!B,$(subst !,!1,$1)))))))))).
_walk = $(if $2,$(if $(findstring s,$(flavor $(word 1,$2).$1)),$2,$(call _walk,$1,$(call _chp+,$2))))
_wildcard = $(if $(call _set,'globLog,$(sort $('globLog) $1)),)$(wildcard $1)
get = $(foreach _self,$2,$(foreach _class,$(if $(findstring $[,$(_self)),$(or $(filter-out |%,$(subst $[, |,$(filter %$],$(_self)))),$(_E0)),$(if $(findstring $],$(_self)),$(_E0),_File)),$(call .,$1)))

ifndef minionStart
  $(eval $(value _epilogue))
else
  minionEnd = $(eval $(value _epilogue))
endif
