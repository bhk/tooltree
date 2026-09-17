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
# Unprefixed Variables
#--------------------------------

# V defaults to the first word of Variants.all
V ?= $(word 1,$(Variants.all))

# All Minion build products are placed under this directory
OUTDIR ?= .out/

# Build products for the current V are placed here
VOUTDIR ?= $(OUTDIR)$(if $V,$V/)

minionCache ?=
minionNoCache ?=
minionStart ?=

# Character constants

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
[[ := {
]] := }
[ := (
] := )
; := ,
\q = "#"
define \n


endef
# This character may not appear in `command` values, except via _lazy.
\e = 


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
_Clean.in = $(patsubst %,Clean(%),$(call get,needs,{ids}))
_Clean.command = $(foreach i,{ids},\
  $(if $(call _hasProperty,cleanCommand,$i),$(call get,cleanCommand,$i),rm -f $(call get,out,$i)))


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
_Write.command = @$(call _printf,{data}) > {@}
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
{@} : {^} $(call get,out,{upIDs} {depsIDs}) | $(call get,out,{ooIDs})
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
_Builder.^ = $(call get,out,{inIDs})

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
_Builder.up^ = $(call get,out,{upIDs})

# oo: order-only dependencies; these may be phony targets, so we allow aliases
_Builder.oo =
_Builder.ooIDs = $(call _expand,{oo},oo)

# deps: direct dependencies not covered by {in} or {up}
_Builder.deps =
_Builder.depsIDs = $(call _expand,{deps},deps)
_Builder.deps^ = $(call get,out,{depsIDs})

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
# Function definitions
#--------------------------------

_eq? = $(findstring $(subst x$1,1,x$2),1)
_shellQuote = '$(subst ','\'',$1)'#'  (comment to fix font coloring)
_printfEsc = $(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1)))
_printf = printf "%b" $(call _shellQuote,$(_printfEsc))

# Quote a (possibly multi-line) $1
_qvn = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)  | ,$(\n)$1),$2$1$2)
_qv = $(call _qvn,$1,')#'

# $(call _?,FN,ARGS..) : same as $(call FN,ARGS..), but logs args & result.
_? = $(call __?,$$(call $1,$2,$3,$4,$5),$(call $1,$2,$3,$4,$5))
# $(call __?,VALUE) print & return VALUE
__? = $(info $1 -> $(call _qvn,$2))$2
# $(call _0?)  -->  "(fn 'arg1' 'arg2' ...)"
_0? = ($0 $(call _argListDesc,$1,$2,$3,$4,$5,$6,$7,$8,$9))
_argListDesc = $(if $1$2$3$4$5$6$7$8$9, '$1'$(call _argListDesc,$2,$3,$4,$5,$6,$7,$8,$9))
_trace = $(foreach f,$1,$(eval $f = $$(call __?,$$(_0?),$(value $f))))

# $(call __?,VALUE)      : instrument a value
# $(call _0?)            : (fn args...)
# $(call _?,FN,ARGS..): same as $(call FN,ARGS..), but logs args & result.

# $(call _log,VALUE,NAME): Output "NAME: VALUE" when NAME matches the
#   pattern in `$(minionDebug)`.
_log = $(if $(filter $(minionDebug),$2),$(info $2: $(call _qvn,$1)))

# $(call _eval,VALUE,NAME): Log + eval VALUE
_eval = $(call _log,$1,EVAL:$2)$(eval $1)

# $(call _evalRules,IDs,EXCLUDES) : Evaluate rules of IDs and their transitive dependencies
_evalRules = $(foreach i,$(call _rollupEx,$(sort $(_isInstance)),$2),$(call _eval,$(call get,rule,$i),$i))

# Construct Make source code that expands to $1, either on the RHS of a
#   variable assignment or within a $(call ...) expression.  It is assumed
#   that $1 does *not* contain '#' or newlines.
_escape = $(subst $[,$$[,$(subst $],$$],$(subst $;,$$;,$(subst $$,$$$$,$1))))

# Is $1 a "safe" arg to "rm -rf"?  (Catch accidental ".", "..", "/" etc.)
_safeToClean = $(if $(filter-out . ..,$(subst /, ,$1)),$1)

# $(call _vvEnc,DATA,OUTFILE) : Encode DATA to be shell-safe (within single
#   quotes) and Make-safe (within double-quotes or RHS of assignment) and
#   to work with /bin/echo and various shell echo builtins.  $2 is substituted
#   with "!@" just to reduce size.
_vvEnc = .$(subst ',`,$(subst ",!`,$(subst `,!b,$(subst $$,!S,$(subst $(\n),!n,$(subst $(\t),!+,$(subst \#,!H,$(subst $2,!@,$(subst \,!B,$(subst !,!1,$1)))))))))).#'

# $(call _lazy,MAKESRC) : Encode MAKESRC for inclusion in a recipe so that
#    it will be expanded when and if the recipe is executed.  Otherwise, all
#    "$" characters will be escaped to avoid expansion by Make. For example:
#    $(call _lazy,$$(info X=$$X))
_lazy = $(subst $$,$(\e),$1)

# Indent recipe lines and escape them for rule-phase expansion.  Un-escape
#    _lazy encoding to enable late (rule phase) evaulation.
_recipe = $(subst $(\e),$$,$(subst $$,$$$$,$(subst $(\t)$(\n),,$(subst $(\n),$(\n)$(\t),$(\t)$1)$(\n))))

# write out this many rules per printf command line
_cacheGroupSize ?= 40


#--------------------------------
# Help system
#--------------------------------

define _helpMessage
Minion v1.1b4 usage:

   make                     Build the target named "default"
   make GOALS...            Build the named goals
   make help                Show this message
   make help GOALS...       Describe the named goals
   make help 'C(A).P'       Compute value of property P for C(A)
   make graph               Show graph of dependencies for "default"
   make clean               `$(call get,command,Alias(clean))`

Goals can be ordinary Make targets, Minion instances (`Class(Arg)`),
variable indirections (`@var`), or aliases. Note that instances must
be quoted for the shell.

endef

_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),(none))

_isProp = $(filter $].%,$(lastword $(subst $], $],$1)))

# instance, indirection, alias, other
_goalType = $(if $(_isProp),Property,$(if $(_isInstance),$(if $(_isClassInvalid),InvalidClass,Instance),$(if $(_isIndirect),Indirect,$(if $(_isAlias),Alias,Other))))

_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(call filter-out,$(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))

define _helpInvalidClass
"$1" looks like an instance with an invalid class name;
`$(_idC).inherit` is not defined.  Perhaps a typo?

endef

# expand lazy-quoting of command to make it readable
_renc = $(subst $(\e),$$,$(subst $$,$$$$,$1))

define _helpInstance
$1 is an instance.

{out} = $(call get,out,$1)
$(if $(call _hasProperty,command,$1),
Command: $(call _qvn,$(call _renc,$(call get,command,$1))),
{rule} = $(call _qvn,$(call get,rule,$1)))

$(_helpDeps)
endef

define _helpIndirect
"$1" is an indirection on the following $(if $(findstring *,$(_ivar)),wildcard:

   $(_ivar),variable:

$(call _describeVar,$(_ivar),   ))

It expands to the following targets: $(call _fmtList,$(call _expand,$1))
endef

define _helpAlias
"$1" is an alias for $(_isAlias).

It is defined by:$(foreach v,$(filter Alias($1).%,$(.VARIABLES)),
$(call _describeVar,$v,   )
)
$(call _helpDeps,$(_isAlias))

It generates the following rule: $(call _qvn,$(call get,rule,$(_isAlias)))
endef

# $1 = C(A).P; $2 = description;  $(id) = C(A); $p = P
define _helpPropertyInfo
$(id) inherits from: $(call _chain,$(call _idC,$(id)))

{$p} $(if $(if $2,,1),is not defined!,is defined by:

$2

Its value is: $(call _qv,$(call get,$p,$(id))))

endef

_helpProperty = $(foreach p,$(or $(lastword $(subst $].,$] ,$1)),$(error Empty property name in $1)),$(foreach id,$(patsubst %$].$p,%$],$1),$(call _helpPropertyInfo,$1,$(call _describeProp,$(id),$p))))

define _helpOther
Target "$1" is not generated by Minion.  It may be a source
file or a target defined by a rule in the Makefile.
endef

_help! = $(info $(call _help$(call _goalType,$1),$1)$(\n))


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
    %: ; @echo 'Cannot build "$*" alongside $$(...)' && false
  else ifneq "" "$(and $(filter clean help,$(__modeKey)),$(__modeArgs))"
    # help or clean mode
    ifeq "help" "$(__modeKey)"
       _error = $(info $(subst $(\n),$(\n)   ,ERROR: $1)$(\n))
       _goalIDs := _Goal(help) $(patsubst %,_HelpGoal(%),$(__modeArgs))
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
    # Avoid cache: Trivial goals do not benefit, and importantly, we avoid
    # the cache when handling `help` (goals may conflict with cached rules,
    # because they take on a new meaning) or `clean` (so we can recover from
    # a corrupted cache file).
  else ifneq "" "$(filter c%,$(foreach v,$(filter-out V,$(_minionStartVars)),$(origin $v)))"
    # Avoid cache: a command-line override was used
  else
    # Use a rule cache file. Recipe expansion is costly, so defer it to rule
    # processing time, only when-and-if the cache needs to be built.
    $(VOUTDIR)cache.mk : $(MAKEFILE_LIST) ; $(call _rulecacheRecipe,$@)
    -include $(VOUTDIR)cache.mk
    # The following line only has an effect when the rule cache does not
    # exist yet.  In that case, it avoids rule generation, because we know
    # Make will immediately restart, and that would be wasted work.
    _cachedIDs ?= %
  endif

  $(call _log,$(_goalIDs),_goalIDs)
  $(call _evalRules,$(_goalIDs),$(_cachedIDs))
endef


# SCAM source exports:

# base.scm

_error = $(error $1)
_isInstance = $(filter %$],$1)
_isIndirect = $(if $(findstring @,$1),$(filter-out %$],$1))
_isAlias = $(if $(filter f% o%,$(origin $1)),Alias($1))
_buildGoalID = $(if $(or $(_isInstance),$(_isIndirect)),_BuildGoal($1),$(_isAlias))
_set = $(eval $$1 := $$2)$2
_wildcard = $(if $(call _set,'globLog,$(sort $('globLog) $1)),)$(wildcard $1)
_shell = $(if $(call _set,'shellLog,$(sort $('shellLog) $(subst $(\s),!0,$(subst $(\t),!+,$(subst !,!1,$1))))),)$(shell $1)
_var = $(if $(call _set,'varLog,$(sort $('varLog) $1)),)$($1)
_ivar = $(filter-out %@,$(subst @,@ ,$1))
_EI = $(call _error,$(if $(filter %@,$1),Invalid target (ends in '@'): $1,Indirection '$1' references undefined variable '$(_ivar)')$(if $2,$(\n)Found while expanding $(if $(filter _BuildGoal$[%,$2),command line goal,$2)))
_expandX = $(foreach w,$1,$(or $(filter %$],$w),$(if $(findstring @,$w),$(foreach x,$(or $(call _ivar,$w),=@),$(patsubst %,$(if $(filter @%,$w),%,$(subst $(\s),,$(filter %( %% ),$(subst @,$[ ,$w) % $(subst @, $] ,$w)))),$(if $(findstring *,$x),$(call _wildcard,$x),$(if $(filter u%,$(flavor $x)),$(call _EI,$w,$2),$(call _expandX,$($x),$x))))),$(or $(if $(filter f% o%,$(origin $w)),Alias($w)),$w))))
_expand = $(call _expandX,$1,$(_self).$2)
_fset = $(eval $$1 = $(if $(filter 1,$(word 1,1$20)),$$(or ))$(subst \#,$$(\H),$(subst $(\n),$$(\n),$2)))$1
_once = $(if $(filter u%,$(flavor _o~$1)),$(call _set,_o~$1,$($1)),$(value _o~$1))
_argError = $(call _error,Argument '$(subst `,,$1)' is mal-formed:$(\n)   $(subst `,,$(subst `$], *$]* ,$(subst `$[, *$[*,$1)))$(\n)$(if $(C),during evaluation of $(C)($(A))))
_argGroup = $(if $(findstring `$[,$(subst $],$[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) `$],$]` ,$(patsubst `$[%,`$[% ,$(subst `$], `$],$(subst `$[, `$[,$1)))),$(if $(filter %`,$w),$(subst `,,$w),$w))),$1)),$1)
_argHash2 = $(subst `,,$(foreach w,$(subst $(if ,,`,), ,$(call _argGroup,$(subst :,`:,$(subst $;,$(if ,,`,),$(subst $],`$],$(subst $[,`$[,$1)))))),$(if $(findstring `:,$w),,:)$w))
_argHash = $(if $(or $(findstring $[,$1),$(findstring $],$1),$(findstring :,$1)),$(or $(value _h~$1),$(call _set,_h~$1,$(_argHash2))),:$(subst $;, :,$1))
_hashGet = $(patsubst $2:%,%,$(filter $2:%,$1))
_describeVar = $2$(if $(filter r%,$(flavor $1)),$(if $(findstring $(\n),$(value $1)),$(subst $(\n),$(\n)$2,define $1$(\n)$(value $1)$(\n)endef),$1 = $(value $1)),$1 := $(subst $(\n),$$(\n),$(subst $$,$$$$,$(value $1))))

# objects.scm

_E0 = $(call _error,Mal-formed target '$(_self)'; $(if $(filter $[%,$(_self)),no CLASS before '$[',$(if $(findstring $[,$(_self)),no '$]' at end,unbalanced '$]')))
_idC = $(if $(findstring $[,$1),$(word 1,$(subst $[, ,$1)))
_isClassInvalid = $(filter u%,$(flavor $(_idC).inherit))
_chp+ = $(if $(filter %$],$1),$(_idC),$(filter-out &%,$($(word 1,$1).inherit) &$1))
_walk = $(if $2,$(if $(findstring s,$(flavor $(word 1,$2).$1)),$2,$(call _walk,$1,$(call _chp+,$2))))
_hasProperty = $(if $(or $(findstring s,$(flavor $2.$1)),$(call _walk,$1,$(filter-out $(\s)|%,$(subst $[, |,$2)))),1)
_E1 = $(call _error,Undefined property {$1} for $(_self) was referenced$(if $3, by {inherit$(if $(findstring .$1=,$3=),, $1)} in,$(if $2, from))$(if $(or $3,$2),:$(\n)$(call _describeVar,$(if $3,$3,$(if $(filter &%,$2),$(word 1,$(call _walk,$(lastword $(subst .,. ,$2)),$(patsubst &%,%,$(word 1,$(subst ., .,$2))))).$(lastword $(subst .,. ,$2)),$2)),   ))$(if $(filter u%,$(flavor $(_class).inherit)),$(\n) NOTE: $(_class).inherit is not defined!$(\n)))
_cxInherit = $(call _cxMemo,$1,$(or $(call _walk,$1,$(call _chp+,$2)),$(call _E1,$1,,$3)))
_cxTok = $(patsubst {%},$$(call!0.,%,$$0),$(if $(findstring {inherit,$1),$(foreach w,$1,$(if $(filter {inherit} {inherit!0%},$w),$$(call!0$(subst $(\s),!0,$(call _cxInherit,$(if $(filter {inherit},$w),$2,$(patsubst {inherit!0%},%,$w)),$3,$4))),$w)),$1))
_cx = $(foreach w,$(word 1,$2).$1,$(if $(filter s%,$(flavor $w)),$(subst $$,$$$$,$(value $w)),$(if $(findstring {,$(value $w)),$(subst !1,!,$(subst !+,	,$(subst !0, ,$(subst $(\s),,$(call _cxTok,$(subst {inherit!0 ,{inherit!0,$(subst !0,!0 ,$(subst $;,$(if ,, , ),$(subst $], $] ,$(subst $[, $[ ,$(subst },} ,$(subst {, {,$(subst $(\s),!0,$(subst $(\t),!+,$(subst !,!1,$(value $w))))))))))),$1,$2,$w))))),$(value $w))))
_cxMemo = $(if $(filter r%,$(flavor &$2.$1)),&$2.$1,$(call _fset,&$2.$1,$(call _cx,$1,$2)))
. = $(if $(filter s%,$(flavor ~$(_self).$1)),$(value ~$(_self).$1),$(call _set,~$(_self).$1,$(if $(findstring s,$(flavor $(_self).$1)),$(foreach 0,&$(_self).$1,$(call or,$(call _cx,$1,$(_self)))),$(call $(if $(filter r%,$(flavor &$(_class).$1)),&$(_class).$1,$(call _fset,&$(_class).$1,$(call _cx,$1,$(or $(call _walk,$1,$(_class)),$(call _E1,$1,$2,)))))))))
get = $(foreach _self,$2,$(foreach _class,$(if $(findstring $[,$(_self)),$(or $(filter-out |%,$(subst $[, |,$(filter %$],$(_self)))),$(_E0)),$(if $(findstring $],$(_self)),$(_E0),_File)),$(call .,$1)))
_argText = $(patsubst $(_class)(%),%,$(_self))
_args = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))))
_arg1 = $(word 1,$(_args))
_namedArgs = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))),$1)
_namedArg1 = $(word 1,$(_namedArgs))
_describeProp = $(if $1,$(if $(filter u%,$(flavor $(word 1,$1).$2)),$(call _describeProp,$(or $(_idC),$(_chp+)),$2),$(call _describeVar,$(word 1,$1).$2,   )$(if $(and $(filter r%,$(flavor $(word 1,$1).$2)),$(findstring {inherit},$(value $(word 1,$1).$2))),$(\n)$(\n)...wherein {inherit} references:$(\n)$(\n)$(call _describeProp,$(or $(_idC),$(_chp+)),$2))))
_chain = $(if $1,$(call _chain,$(_chp+),$2 $(word 1,$1)),$(filter %,$2))
_badAuto = $(call _error,$$$$$1 was evaluated prior to rule processing$(\n)during evaluation of $(if $(filter &%,$2),$(word 1,$(patsubst &%,%,$2)),$$(call $2,...))$(if $(_self), in context of $(_self)))

# tools.scm

_inferIDs = $(if $2,$(foreach w,$1,$(or $(filter %$],$(patsubst %$(or $(suffix $(if $(filter %$],$w),$(call get,out,$w),$w)),.),%($w),$2)),$w)),$1)
_depsOf = $(or $(value _&deps-$1),$(call _set,_&deps-$1,$(or $(sort $(foreach w,$(filter %$],$(call get,needs,$1)),$w $(call _depsOf,$w))),$(if ,, ))))
_rollup = $(sort $(foreach w,$(filter %$],$1),$w $(call _depsOf,$w)))
_rollupEx = $(if $1,$(call _rollupEx,$(filter-out $3 $1,$(sort $(filter %$],$(call get,needs,$(filter-out $2,$1))) $(foreach w,$(filter $2,$1),$(value _$w_needs)))),$2,$3 $1),$(filter-out $2,$3))
_relpath = $(if $(filter /%,$2),$2,$(if $(filter ..,$(subst /, ,$1)),$(error _relpath: '..' in $1),$(or $(foreach w,$(filter %/%,$(word 1,$(subst /,/% ,$1))),$(call _relpath,$(patsubst $w,%,$1),$(if $(filter $w,$2),$(patsubst $w,%,$2),../$2))),$2)))
_group = $(if $1,$(subst | ,|0,$(subst ||,,$(join $(subst |,|1,$1),$(subst $(patsubst %,|,$(wordlist 1,$2,$1)),$(patsubst %,|,$(wordlist 1,$2,$1))|,$(patsubst %,|,$1))) )))
_ungroup = $(subst |1,|,$(subst |0, ,$1))
_graph = $(if $4,$(call _graph,$1,$2,$3,$(wordlist 2,99999999,$4),$(subst ``,` ,$(filter-out %9,$(subst `  ,``,$(patsubst `,` ,$(subst `$(word 1,$4)`,`,$5) `$(subst $(\s),,$(addsuffix `,$(call $1,$3,$(word 1,$4)))) 9)))),$6$(foreach w,$5,$(if $(filter `,$w), ,|)  )$(\n)$(foreach w,$5,$(if $(findstring `$(word 1,$4)`,$w),+->,$(if $(filter `,$w), ,|)  ))$(if $5, )$(call $2,$3,$(word 1,$4))$(\n)),$6)
_traverse = $(if $(word 1,$3),$(call _traverse,$1,$2,$(call $1,$2,$(word 1,$3)) $(wordlist 2,99999999,$3),$(filter-out $(word 1,$3),$4) $(word 1,$3)),$4)
_graphDeps = $(call _graph,$1,$2,$3,$(call _traverse,$1,$3,$4))
_uniqQ = $(if $1,$(word 1,$1)   $(call _uniqQ,$(filter-out $(word 1,$1),$1)))
_unique = $(filter %,$(subst ^c,^,$(subst ^p,%,$(call _uniqQ,$(subst %,^p,$(subst ^,^c,$1))))))
_rulecacheRecipe = $(info Updating Minion cache...)$(call _rcr2,$1,$(call _rollup,$(call _varToIDs,minionCache)),$(filter %$],$(call _varToIDs,minionNoCache)),$(_cacheGroupSize))
_rcr2 = @mkdir -p $(dir $1)$(\n)@> $1_tmp_$(\n)$(foreach w,$(call _group,$(filter-out $3,$2),$4),@$(call _printf,$(foreach x,$(call _ungroup,$w),$(\n)$(call get,rule,$x)$(if $3,$(\n)_$x_needs = $(filter $3,$(call _depsOf,$x)))$(\n))) >> $1_tmp_$(\n))@$(call _printf,_cachedIDs = $(filter-out $3,$2)$(\n)$(foreach w,minionCache minionNoCache $('varLog),$(call _checkValue,$1,$($w),$$($w)))$(if $('globLog),$(call _checkValue,$1,$(wildcard $('globLog)),$$(wildcard $('globLog))))$(foreach w,$('shellLog),$(call _checkValue,$1,$(shell $(subst !1,!,$(subst !+,	,$(subst !0, ,$w)))),$$(shell $(subst !1,!,$(subst !+,	,$(subst !0, ,$w))))))) >> $1_tmp_$(\n)@mv $1_tmp_ $1$(\n)
_varToIDs = $(foreach w,$(call _expand,$($1)),$(if $(filter %$],$w),$w,$(error $1 references unknown target '$w')))
_checkValue = $(\n)ifneq "$(call _qesc,$2)" "$3"$(\n)  $1: $$(_forceTarget)$(\n)endif$(\n)
_qesc = $(subst $(\n),$$($(\n)),$(subst \#,$$(\H),$(subst ",$$(\q),$(subst $$,$$$$,$1))))

# outputs.scm

_fsenc = $(subst },@R,$(subst {,@L,$(subst >,@r,$(subst <,@l,$(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst :,@C,$(subst *,@S,$(subst $],@-,$(subst $[,@+,$(subst |,@1,$(subst @,@_,$1)))))))))))))
_outBX = $(subst @D,/,$(subst $(\s),,$(patsubst /%@_,_%@,$(addprefix /,$(subst @_,@_ ,$(_fsenc))))))
_outBS = $(_fsenc)$(if $(findstring %,$3),,$(suffix $4))$(if $4,$(patsubst _/$(VOUTDIR)%,_%,$(if $(filter %$],$2),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,/$4))))))),$(call _outBX,$2))
_outBasis = $(if $(filter $5,$2),$(_outBS),$(call _outBS,$1$(subst _$(or $5,|),_|,_$2),$(or $5,out),$3,$4))

ifndef minionStart
  $(eval $(value _epilogue))
else
  minionEnd = $(eval $(value _epilogue))
endif
