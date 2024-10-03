# minion.mk

# User Classes
#
# The following classes may be overridden by user makefiles.  Minion
# attaches no property definitions to them; it just provides a default
# inheritance.  User makefiles may not override other make variables defined
# in this file, except for a few cases where "?=" is used (see below).

CC++.inherit ?= _CC++
CC.inherit ?= _CC
Compile.inherit ?= _Compile
Copy.inherit ?= _Copy
Exec.inherit ?= _Exec
GZip.inherit ?= _GZip
Link.inherit ?= _Link
LinkC++.inherit ?= _LinkC++
LinkC.inherit ?= _LinkC
Mkdir.inherit ?= _Mkdir
Phony.inherit ?= _Phony
Print.inherit ?= _Print
Remove.inherit ?= _Remove
Run.inherit ?= _Run
Tar.inherit ?= _Tar
Test.inherit ?= _Test
Touch.inherit ?= _Touch
Unzip.inherit ?= _Unzip
Write.inherit ?= _Write
Zip.inherit ?= _Zip


#--------------------------------
# Built-in Classes
#--------------------------------

# Alias(TARGETNAME) : Generate a phony rule whose {out} matches TARGETNAME.
#     {command} and/or {in} are supplied by the user makefile.
#
Alias.inherit = Phony
Alias.out = $(subst :,\:,$(_argText))
Alias.in =


# Variants(TARGETNAME) : Build {all} variants of TARGETNAME.  Each variant
#    is defined in a separate rule so they can all proceed concurrently.
#
Variants.inherit = Phony
Variants.in = $(foreach v,{all},_Variant($(_argText),V:$v))


# _Variant(TARGETNAME,V:VARIANT) : Build VARIANT of TARGETNAME.
#
_Variant.inherit = Phony
_Variant.in =
_Variant.command = @$(MAKE) -f $(word 1,$(MAKEFILE_LIST)) --no-print-directory $(call _shellQuote,$(subst =,:,$(_arg1))) V=$(call _shellQuote,$(call _namedArg1,V))


# _Phony(INPUTS) : Generate a phony rule.
#
#   A phony rule does not generate an output file.  Therefore, Make cannot
#   determine whether its result is "new" or "old", so it is always
#   considered "old", and its recipe will be executed whenever it is listed
#   as a target.
#
_Phony.inherit = _IsPhony Builder
_Phony.command = @true
_Phony.message =


# _IsPhony : Mixin that defines properties as appropriate for all phony
#    targets; can be used to make any class phony.
#
_IsPhony.rule = .PHONY: {@}$(\n){inherit}
_IsPhony.mkdirs = # not a real file => no need to create directory
_IsPhony.vvFile = # always runs => no point in validating


# _Compile(SOURCE) : Base class for invoking a compiler.
#
_Compile.inherit = Builder
_Compile.outExt = .o
_Compile.command = {compiler} -c -o {@} {<} {flags} -MMD -MP -MF {depsFile}
_Compile.depsFile = {@}.d
_Compile.rule = {inherit}-include {depsFile}$(\n)
_Compile.flags = {optFlags} {warnFlags} {libFlags} $(addprefix -I,{includes})
_Compile.optFlags =
_Compile.warnFlags =
_Compile.libFlags =
_Compile.includes =


# _CC(SOURCE) : Compile a C file to an object file.
#
_CC.inherit = Compile
_CC.compiler = gcc


# _CC++(SOURCE) : Compile a C++ file to an object file.
#
_CC++.inherit = Compile
_CC++.compiler = g++


# _Link(INPUTS) : Link an executable.
#
_Link.inherit = Builder
_Link.outExt =
_Link.command = {compiler} -o {@} {^} {flags} 
_Link.flags = {libFlags}
_Link.libFlags =


# _LinkC(INPUTS) : Link a command-line C program.
#
_LinkC.inherit = _Link
_LinkC.compiler = gcc
_LinkC.inferClasses = CC.c


# _LinkC++(INPUTS) : Link a command-line C++ program.
#
_LinkC++.inherit = _Link
_LinkC++.compiler = g++
_LinkC++.inferClasses = CC.c CC++.cpp CC++.cc


# _Exec(COMMAND) : Run a command, capturing what it writes to stdout.
#
#    By default, the first ingredient is an executable or shell command, and
#    it is passed as arguments the {execArgs} property and all other
#    ingredients.  Override {exec} to change what is to be executed while
#    retaining other behavior.
#
_Exec.inherit = Builder
_Exec.command = ( {exportPrefix} {exec} ) > {@} || ( rm -f {@}; false )
_Exec.exec = {<} {execArgs} $(wordlist 2,9999,{^})
_Exec.execArgs =
_Exec.outExt = .out


# Test(COMMAND) : Run a command (as per Exec) updating an OK file on success.
#
_Test.inherit = Exec
_Test.command = {exportPrefix} {exec}$(\n)touch {@}
_Test.outExt = .ok


# _Run(COMMAND) : run command (as per Exec).
#
_Run.inherit = _IsPhony Exec
_Run.command = {exportPrefix} {exec}


# _Copy(INPUT)
# _Copy(INPUT,out:OUT)
# _Copy(INPUT,dir:DIR)
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


# _Mkdir(DIR) : Create directory
#
_Mkdir.inherit = Builder
_Mkdir.in =
_Mkdir.out = $(_arg1)
_Mkdir.mkdirs =
_Mkdir.vvFile = # without {mkdirs}, this will fail
_Mkdir.command = mkdir -p {@}


# _Touch(FILE) : Create empty file
#
_Touch.inherit = Builder
_Touch.in =
_Touch.out = $(_arg1)
_Touch.command = touch {@}


# _Remove(FILE) : Remove FILE from the file system
#
_Remove.inherit = Phony
_Remove.in =
_Remove.command = rm -f $(_arg1)


# _Print(INPUT) : Write artifact to stdout.
#
_Print.inherit = Phony
_Print.command = @cat {<}


# _Tar(INPUTS) : Construct a TAR file
#
_Tar.inherit = Builder
_Tar.outExt = .tar
_Tar.command = tar -cvf {@} {^}


# _GZip(INPUT) :  Compress an artifact.
#
_GZip.inherit = Exec
_GZip.exec = gzip -c {^}
_GZip.outExt = %.gz


# _Zip(INPUTS) : Construct a ZIP file
#
_Zip.inherit = Builder
_Zip.outExt = .zip
_Zip.command = zip {@} {^}


# _Unzip(OUT) : Extract from a zip file
#
#   The argument is the name of the file to extract from the ZIP file.  The
#   ZIP file name is based on the class name.  Declare a subclass with the
#   appropriate name, or override its `in` property to specify the zip file.
#
_Unzip.inherit = Builder
_Unzip.command = unzip -p {<} $(_argText) > {@} || rm {@}
_Unzip.in = $(_class).zip


# _Write(VAR)
# _Write(VAR,out:OUT)
#
#   Write the value of a variable to a file.
#
_Write.inherit = Builder
_Write.out = $(or $(call _namedArg1,out),{inherit})
_Write.command = @$(call _printf,{data}) > {@}
_Write.data = $($(_arg1))
_Write.in =

# Builder(ARGS):  Base class for builders.

# Shorthand properties
Builder.@ = {out}
Builder.< = $(firstword {^})
Builder.^ = {inFiles}

# `needs` should include all explicit dependencies and any instances
# required to build auto-generated implicit dependencies (which should be
# included in `ooIDs`).
Builder.needs = {inIDs} {upIDs} {depsIDs} {ooIDs}

# `in` is the user-supplied set of "inputs", in the form of a target list
# (targets or indirections).  It is intended to be easily overridden
# on a per-class or per-instance basis.
#
# The actual set of prerequisites differs from `in` in a few ways:
#  - Indirections are expanded
#  - Inference (as per `inferClasses`) may replace targets with
#    intermediate results.
#  - `up` targets are also dependencies (but not "inputs")
#
Builder.in = $(_args)

# list of ([ID,]FILE) pairs for inputs
Builder.inPairs = $(call _inferPairs,$(foreach i,$(call _expand,{in},in),$i$(if $(filter %$],$i),$$$(call get,out,$i))),{inferClasses})

Builder.inIDs = $(call _pairIDs,{inPairs})
Builder.inFiles = $(call _pairFiles,{inPairs})

# `up` lists dependencies that are typically specified by the class itself,
# not by the instance argument or `in` property.
Builder.up =
Builder.upIDs = $(call _expand,{up},up)
Builder.up^ = $(call get,out,{upIDs})

# `oo` lists order-only dependencies.
Builder.oo =
Builder.ooIDs = $(call _expand,{oo},oo)

# `deps` lists implicit dependencies: artifacts that are not listed on the
# command line, but that (may) affect the output file anyway.
Builder.deps =
Builder.depsIDs = $(call _expand,{deps})
Builder.deps^ = $(call get,out,{depsIDs})

# `inferClasses` a list of words in the format "CLASS.EXT", implying
# that each input filename ending in ".EXT" should be replaced with
# "CLASS(FILE.EXT)".  This is used to, for example, convert ".c" files
# to ".o" when they are provided as inputs to a LinkC instance.
Builder.inferClasses =

# Note: By default, `outDir`, `outName`, and `outExt` are used to
# construct `out`, but any of them can be overridden.  Do not assume
# that, for example, `outDir` is always the same as `$(dir {out})`.
Builder.out = {outDir}{outName}
Builder.outDir = $(dir {outBasis})
Builder.outName = $(call _applyExt,$(notdir {outBasis}),{outExt})
Builder.outExt = %
Builder.outBasis = $(VOUTDIR)$(call _outBasis,$(_class),$(_argText),{outExt},$(call get,out,$(filter $(_arg1),$(word 1,$(call _expand,{in},in)))),$(_arg1))

_applyExt = $(basename $1)$(subst %,$(suffix $1),$2)

# Message to be displayed when/if the command executes.  By default, Minion
# clases display this for non-phony rules.  The user can assign this
# variable an empty value to prevent these messages.
Builder.message ?= \#-> $(_self)

Builder.mkdirs = $(sort $(dir {@} {vvFile}))

# This may be prepended to individual command lines to export environment variables
# listed in {exports}
Builder.exportPrefix = $(foreach v,{exports},$v=$(call _shellQuote,{$v}) )
Builder.exports =

# Validity value
#
# If {vvFile} is non-empty, the rule will compare {vvValue} will to the
# value it had when the target file was last updated.  If they do not match,
# the target file will be treated as stale.  The user can set this to an
# empty value in order to disable validity checking.
#
Builder.vvFile ?= {outBasis}.vv
Builder.vvValue = $(call _vvEnc,{command},{@})

define Builder.vvRule
_vv =
-include {vvFile}
ifneq "$$(_vv)" "{vvValue}"
  {@}: $(_forceTarget)
endif

endef

# $(call _vvEnc,DATA,OUTFILE) : Encode to be shell-safe (within single
#   quotes) and Make-safe (within double-quotes or RHS of assignment)
#   and echo-safe (across /bin/echo and various shell builtins)
_vvEnc = .$(subst ',`,$(subst ",!`,$(subst `,!b,$(subst $$,!S,$(subst $(\n),!n,$(subst $(\t),!+,$(subst \#,!H,$(subst $2,!@,$(subst \,!B,$(subst !,!1,$1)))))))))).#'


# $(call _lazy,MAKESRC) : Encode MAKESRC for inclusion in a recipe so that
# it will be expanded when and if the recipe is executed.  Otherwise, all
# "$" characters will be escaped to avoid expansion by Make. For example:
# $(call _lazy,$$(info X=$$X))
_lazy = $(subst $$,$(\e),$1)

# Format recipe lines and escape for rule-phase expansion. Un-escape
# _lazy encoding to enable on-demand execution of functions.
_recipeEnc = $(subst $(\e),$$,$(subst $$,$$$$,$1))

# Remove empty lines, prefix remaining lines with \t
_recipe = $(subst $(\t)$(\n),,$(subst $(\n),$(\n)$(\t),$(\t)$1)$(\n))

# A Minion instance's "rule" is all the Make source code required to build
# it.  It contains a Make rule (target, prereqs, recipe) and perhaps other
# statements.
#
define Builder.rule
{@} : {^} {up^} {deps^} | $(call get,out,{ooIDs})
$(call _recipeEnc,$(call _recipe,
$(if {message},@echo $(call _shellQuote,{message}))
$(if {mkdirs},@mkdir -p {mkdirs})
$(if {vvFile},@echo '_vv={vvValue}' > {vvFile})
{command}))
$(if {vvFile},{vvRule})
endef


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


# _Goal(TARGETNAME) : Generate a phony rule for an instance or indirection
#    goal.  Its {out} should match the name provided on the command line,
#    and its {in} is the named instance or indirection.
#
_Goal.inherit = Alias
_Goal.in = $(_argText)


# _HelpGoal(TARGETNAME) : Generate a rule that invokes `_help!`
#
_HelpGoal.inherit = Alias
_HelpGoal.command = @true$(call _lazy,$$(call _help!,$(call _escArg,$(_argText))))

# Makefile(VAR) : Generate a makefile that includes rules for IDs in $(VAR)
#   and their transitive dependencies, excluding IDs in $(VAR_exclude).
#   Include rules that cancel Make's built-in implicit pattern rules.
#
#   Command expansion is deferred to the rule processing phase, so when the
#   makefile is fresh we avoid the time it takes to compute all the rules.
#
Makefile.inherit = Builder
Makefile.in = $(MAKEFILE_LIST)
Makefile.vvFile = # too costly; defeats the purpose
Makefile.command = $(call _lazy,$$(call get,lazyCommand,$(call _escArg,$(_self))))
Makefile.excludeIDs = $(filter %$],$(call _expand,$($(_argText)_exclude)))
Makefile.IDs = $(filter-out {excludeIDs},$(call _rollup,$(call _expand,@$(_argText))))
define Makefile.lazyCommand
$(call _recipe,
@rm -f {@}
@echo '_cachedIDs = {IDs}' > {@}_tmp_
$(foreach i,{IDs},
@$(call _printf,$(call get,rule,$i)
$(if {excludeIDs},_$i_needs = $(filter {excludeIDs},$(call _depsOf,$i))
)) >> {@}_tmp_)
@echo 'a:' | $(MAKE) -pf - | sed '/^[^: ]*%[^: ]*\::* /!d' >> {@}_tmp_
@mv {@}_tmp_ {@})
endef


# Include(MAKEFILE) : Include a makefile.
#
Include.out =
Include.needs = $(_argText)
Include.rule = -include $(call get,out,$(_argText))


#--------------------------------
# Variable & Function Definitions
#--------------------------------

# V defaults to the first word of Variants.all
V ?= $(word 1,$(Variants.all))

# All Minion build products are placed under this directory
OUTDIR ?= .out/

# Build products for the current V are placed here
VOUTDIR ?= $(OUTDIR)$(if $V,$V/)

# $(call minion_alias,GOAL) returns an instance if GOAL is an alias,
#   or an empty value otherwise.  User makefiles can override this to
#   support other types of aliases.
minion_alias ?= $(_aliasID)

# Character constants

\s := $(if ,, )
\t := $(if ,,	)
\H := \#
[[ := {
]] := }
[ := (
] := )
; := ,
define \n


endef
# This character may not appear in `command` values, except via _lazy.
\e = 

_eq? = $(findstring $(subst x$1,1,x$2),1)
_shellQuote = '$(subst ','\'',$1)'#'  (comment to fix font coloring)
_printfEsc = $(subst $(\n),\n,$(subst $(\t),\t,$(subst \,\\,$1)))
_printf = printf "%b" $(call _shellQuote,$(_printfEsc))

# Quote a (possibly multi-line) $1
_qv = $(if $(findstring $(\n),$1),$(subst $(\n),$(\n)  | ,$(\n)$1),'$1')

# $(call _?,FN,ARGS..): same as $(call FN,ARGS..), but logs args & result.
_? = $(call __?,$$(call $1,$2,$3,$4,$5),$(call $1,$2,$3,$4,$5))
__? = $(info $1 -> $2)$2

# $(call _log,NAME,VALUE): Output "NAME: VALUE" when NAME matches the
#   pattern in `$(minion_debug)`.
_log = $(if $(filter $(minion_debug),$1),$(info $1: $(call _qv,$2)))

# $(call _eval,NAME,VALUE): Log + eval VALUE
_eval = $(_log)$(eval $2)

# $(call _evalRules,IDs,EXCLUDES) : Evaluate rules of IDs and their transitive dependencies
_evalRules = $(foreach i,$(call _rollupEx,$(sort $(_isInstance)),$2),$(call _eval,eval-$i,$(call get,rule,$i)))

# Escape an instance argument as a Make function argument
_escArg = $(subst $[,$$[,$(subst $],$$],$(subst $;,$$;,$(subst $$,$$$$,$1))))

#--------------------------------
# Help system
#--------------------------------

define _helpMessage
$(word 1,$(MAKEFILE_LIST)) usage:

   make                     Build the target named "default"
   make GOALS...            Build the named goals
   make help                Show this message
   make help GOALS...       Describe the named goals
   make help 'C(A).P'       Compute value of property P for C(A)
   make clean               `$(call get,command,Alias(clean))`

Goals can be ordinary Make targets, Minion instances (`Class(Arg)`),
variable indirections (`@var`), or aliases. Note that instances must
be quoted for the shell.

endef

_fmtList = $(if $(word 1,$1),$(subst $(\s),$(\n)   , $(strip $1)),(none))

_isProp = $(filter $].%,$(lastword $(subst $], $],$1)))

# instance, indirection, alias, other
_goalType = $(if $(_isProp),Property,$(if $(_isInstance),$(if $(_isClassInvalid),InvalidClass,Instance),$(if $(_isIndirect),Indirect,$(if $(_aliasID),Alias,Other))))

_helpDeps = Direct dependencies: $(call _fmtList,$(call get,needs,$1))$(\n)$(\n)Indirect dependencies: $(call _fmtList,$(call filter-out,$(call get,needs,$1),$(call _rollup,$(call get,needs,$1))))


define _helpInvalidClass
"$1" looks like an instance with an invalid class name;
`$(_idC).inherit` is not defined.  Perhaps a typo?

endef


define _helpInstance
"$1" is an instance.

Output: $(call get,out,$1)

Command: $(call _qv,$(call _recipeEnc,$(call get,command,$1)))

$(_helpDeps)
endef


define _helpIndirect
"$1" is an indirection on the following variable:

$(call _describeVar,$(_ivar),   )

It expands to the following targets: $(call _fmtList,$(call _expand,$1))
endef


define _helpAlias
"$1" is an alias for $(minion_alias).
$(if $(filter Alias$[%,$(minion_alias)),
It is defined by:$(foreach v,$(filter Alias($1).%,$(.VARIABLES)),
$(call _describeVar,$v,   )
))
$(call _helpDeps,$(minion_alias))

It generates the following rule: $(call _qv,$(call get,rule,$(minion_alias)))
endef


define _helpProperty
$(foreach p,$(or $(lastword $(subst $].,$] ,$1)),$(error Empty property name in $1)),$(foreach id,$(patsubst %$].$p,%$],$1),$(info $(id) inherits from: $(call _chain,$(call _idC,$(id)))

$1 is defined by:

$(call _describeProp,$(id),$p))
Its value is: $(call _qv,$(call get,$p,$(id)))
))
endef


define _helpOther
Target "$1" is not generated by Minion.  It may be a source
file or a target defined by a rule in the Makefile.
endef


_help! = \
  $(if $(filter help,$1),\
    $(if $(filter-out help,$(MAKECMDGOALS)),,$(info $(_helpMessage))),\
    $(info $(call _help$(call _goalType,$1),$1)))


#--------------------------------
# Rules
#--------------------------------

_forceTarget = $(OUTDIR)FORCE

_OUTDIR_safe? = $(filter-out . ..,$(subst /, ,$(OUTDIR)))

Alias(clean).command ?= $(if $(_OUTDIR_safe?),rm -rf $(OUTDIR),@echo '** make clean is disabled; OUTDIR is unsafe: "$(OUTDIR)"' ; false)

# This will be the default target when `$(minion_end)` is omitted (and
# no goal is named on the command line)
_error_default: ; $(error Makefile used minion_start but did not call `$$(minion_end)`)

.SUFFIXES:
$(_forceTarget):

define _epilogue
  # Check OUTDIR
  ifneq "/" "$(patsubst %/,/,$(OUTDIR))"
    $(error OUTDIR must end in "/")
  endif

  ifndef MAKECMDGOALS
    # .DEFAULT_GOAL only matters when there are no command line goals
    .DEFAULT_GOAL = default
    _goalIDs := $(call _goalID,default)
  else ifneq "" "$(filter $$%,$(MAKECMDGOALS))"
    # "$*" captures the entirety of the goal, including embedded spaces.
    $$%: ; @#$(info $$$* = $(call _qv,$(call or,$$$*)))
    %: ; @echo 'Cannot build "$*" alongside $$(...)' && false
  else ifneq "" "$(filter help,$(MAKECMDGOALS))"
    _goalIDs := $(MAKECMDGOALS:%=_HelpGoal$[%$])
    _error = $(info $(subst $(\n),$(\n)   ,ERROR: $1)$(\n))
  else
    _goalIDs := $(foreach g,$(MAKECMDGOALS),$(call _goalID,$g))
  endif

  ifeq "" "$(strip $(call get,needs,$(_goalIDs)))"
    # Trivial goals do not benefit from a cache.  Importantly, avoid the
    # cache when handling `help` (targets may conflict with cache file) or
    # `clean` (so we can recover from a corrupted cache file).
  else ifdef minion_cache
    $(call _evalRules,Include(Makefile(minion_cache)))
    # If _cachedIDs is unset, the cache must not exist and Make will
    # restart, so skip rule computation.
    _cachedIDs ?= %
  endif

  $(call _evalRules,$(_goalIDs),$(_cachedIDs))
endef


# SCAM source exports:

# base.scm

_error = $(error $1)
_isInstance = $(filter %$],$1)
_isIndirect = $(findstring @,$(filter-out %$],$1))
_aliasID = $(if $(filter s% r%,$(flavor Alias($1).in) $(flavor Alias($1).command)),Alias($1))
_goalID = $(or $(call minion_alias,$1),$(if $(or $(_isInstance),$(_isIndirect)),_Goal($1)))
_ivar = $(filter-out %@,$(subst @,@ ,$1))
_ipat = $(if $(filter @%,$1),%,$(subst $(\s),,$(filter %( %% ),$(subst @,$[ ,$1) % $(subst @, $] ,$1))))
_EI = $(call _error,$(if $(filter %@,$1),Invalid target (ends in '@'): $1,Indirection '$1' references undefined variable '$(_ivar)')$(if $(and $(_self),$2),$(\n)Found while expanding $(if $(filter _Goal$[%,$(_self)),command line goal $(patsubst _Goal(%),%,$(_self)),$(_self).$2)))
_expandX = $(foreach w,$1,$(if $(findstring @,$w),$(if $(findstring $[,$w)$(findstring $],$w),$w,$(if $(filter u%,$(flavor $(call _ivar,$w))),$(call _EI,$w,$2),$(patsubst %,$(call _ipat,$w),$(call _expandX,$($(call _ivar,$w)),$2)))),$w))
_expand = $(if $(findstring @,$1),$(call _expandX,$1,$2),$1)
_set = $(eval $$1 := $$2)$2
_fset = $(eval $$1 = $(if $(filter 1,$(word 1,1$20)),$$(or ))$(subst \#,$$(\H),$(subst $(\n),$$(\n),$2)))$1
_once = $(if $(filter u%,$(flavor _o~$1)),$(call _set,_o~$1,$($1)),$(value _o~$1))
_argError = $(call _error,Argument '$(subst `,,$1)' is mal-formed:$(\n)   $(subst `,,$(subst `$], *$]* ,$(subst `$[, *$[*,$1)))$(\n)$(if $(C),during evaluation of $(C)($(A))))
_argGroup = $(if $(findstring `$[,$(subst $],$[,$1)),$(if $(findstring $1,$2),$(_argError),$(call _argGroup,$(subst $(\s),,$(foreach w,$(subst $(\s) `$],$]` ,$(patsubst `$[%,`$[% ,$(subst `$], `$],$(subst `$[, `$[,$1)))),$(if $(filter %`,$w),$(subst `,,$w),$w))),$1)),$1)
_argHash2 = $(subst `,,$(foreach w,$(subst $(if ,,`,), ,$(call _argGroup,$(subst :,`:,$(subst $;,$(if ,,`,),$(subst $],`$],$(subst $[,`$[,$1)))))),$(if $(findstring `:,$w),,:)$w))
_argHash = $(if $(or $(findstring $[,$1),$(findstring $],$1),$(findstring :,$1)),$(or $(value _h~$1),$(call _set,_h~$1,$(_argHash2))),:$(subst $;, :,$1))
_hashGet = $(patsubst $2:%,%,$(filter $2:%,$1))
_describeVar = $2$(if $(filter r%,$(flavor $1)),$(if $(findstring $(\n),$(value $1)),$(subst $(\n),$(\n)$2,define $1$(\n)$(value $1)$(\n)endef),$1 = $(value $1)),$1 := $(subst $(\n),$$(\n),$(subst $$,$$$$,$(value $1))))

# objects.scm

_idC = $(if $(findstring $[,$1),$(word 1,$(subst $[, ,$1)))
_isClassInvalid = $(filter u%,$(flavor $(_idC).inherit))
_pup = $(filter-out &%,$($(word 1,$1).inherit) &$1)
_walk = $(if $1,$(if $(findstring s,$(flavor $(word 1,$1).$2)),$1,$(call _walk,$(_pup),$2)))
_E1 = $(call _error,Undefined property '$2' for $(_self) was referenced$(if $(filter u%,$(flavor $(_class).inherit)),;$(\n)$(_class) is not a valid class name ($(_class).inherit is not defined),$(if $3,$(if $(filter ^%,$3), from {inherit} in,$(if $(filter &&%,$3), from {$2} in, during evaluation of)):$(\n)$(call _describeVar,$(if $(filter &%,$3),$(foreach w,$(lastword $(subst ., ,$3)),$(word 1,$(call _walk,$(word 1,$(subst &, ,$(subst ., ,$3))),$w)).$w),$(if $(filter ^%,$3),$(subst ^,,$(word 1,$3)).$2,$3)))))$(\n))
_cx = $(if $1,$(if $(value &$1.$2),&$1.$2,$(call _fset,$(if $4,$(subst $],],~$(_self).$2),&$1.$2),$(foreach w,$(word 1,$1).$2,$(if $(filter s%,$(flavor $w)),$(subst $$,$$$$,$(value $w)),$(subst },$(if ,,,&$$0$]),$(subst {,$(if ,,$$$[call .,),$(subst {inherit},$(if $(findstring {inherit},$(value $w)),$$(call $(call _cx,$(call _walk,$(if $4,$(_class),$(_pup)),$2),$2,^$1))),$(value $w)))))))),$(_E1))
.& = $(if $(findstring s,$(flavor $(_self).$1)),$(call _cx,$(_self),$1,$2,1),$(if $(findstring s,$(flavor &$(_class).$1)),&$(_class).$1,$(call _fset,&$(_class).$1,$(value $(call _cx,$(call _walk,$(_class),$1),$1,$2)))))
. = $(if $(filter s%,$(flavor ~$(_self).$1)),$(value ~$(_self).$1),$(call _set,~$(_self).$1,$(call $(.&))))
_E0 = $(call _error,Mal-formed target '$(_self)'; $(if $(filter $[%,$(_self)),no CLASS before '$[',$(if $(findstring $[,$(_self)),no '$]' at end,unbalanced '$]')))
get = $(foreach _self,$2,$(foreach _class,$(if $(findstring $[,$(_self)),$(or $(filter-out |%,$(subst $[, |,$(filter %$],$(_self)))),$(_E0)),$(if $(findstring $],$(_self)),$(_E0),_File)),$(call .,$1)))
_argText = $(patsubst $(_class)(%),%,$(_self))
_args = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))))
_arg1 = $(word 1,$(_args))
_namedArgs = $(call _hashGet,$(call _argHash,$(patsubst $(_class)(%),%,$(_self))),$1)
_namedArg1 = $(word 1,$(_namedArgs))
_describeProp = $(if $1,$(if $(filter u%,$(flavor $(word 1,$1).$2)),$(call _describeProp,$(or $(_idC),$(_pup)),$2),$(call _describeVar,$(word 1,$1).$2,   )$(if $(and $(filter r%,$(flavor $(word 1,$1).$2)),$(findstring {inherit},$(value $(word 1,$1).$2))),$(\n)$(\n)...wherein {inherit} references:$(\n)$(\n)$(call _describeProp,$(or $(_idC),$(_pup)),$2))),Error: no definition found!)
_chain = $(if $1,$(call _chain,$(_pup),$2 $(word 1,$1)),$(filter %,$2))

# tools.scm

_pairIDs = $(filter-out $$%,$(subst $$, $$,$1))
_pairFiles = $(filter-out %$$,$(subst $$,$$ ,$1))
_inferPairs = $(if $2,$(foreach w,$1,$(or $(foreach x,$(word 1,$(filter %$],$(patsubst %$(or $(suffix $(call _pairFiles,$w)),.),%($(call _pairIDs,$w)),$2))),$x$$$(call get,out,$x)),$w)),$1)
_depsOf = $(or $(value _&deps-$1),$(call _set,_&deps-$1,$(or $(sort $(foreach w,$(filter %$],$(call get,needs,$1)),$w $(call _depsOf,$w))),$(if ,, ))))
_rollup = $(sort $(foreach w,$(filter %$],$1),$w $(call _depsOf,$w)))
_rollupEx = $(if $1,$(call _rollupEx,$(filter-out $3 $1,$(sort $(filter %$],$(call get,needs,$(filter-out $2,$1))) $(foreach w,$(filter $2,$1),$(value _$w_needs)))),$2,$3 $1),$(filter-out $2,$3))
_relpath = $(if $(filter /%,$2),$2,$(if $(filter ..,$(subst /, ,$1)),$(error _relpath: '..' in $1),$(or $(foreach w,$(filter %/%,$(word 1,$(subst /,/% ,$1))),$(call _relpath,$(patsubst $w,%,$1),$(if $(filter $w,$2),$(patsubst $w,%,$2),../$2))),$2)))

# outputs.scm

_fsenc = $(subst >,@r,$(subst <,@l,$(subst /,@D,$(subst ~,@T,$(subst !,@B,$(subst :,@C,$(subst $],@-,$(subst $[,@+,$(subst |,@1,$(subst @,@_,$1))))))))))
_outBX = $(subst @D,/,$(subst $(\s),,$(patsubst /%@_,_%@,$(addprefix /,$(subst @_,@_ ,$(_fsenc))))))
_outBS = $(_fsenc)$(if $(findstring %,$3),,$(suffix $4))$(if $4,$(patsubst _/$(OUTDIR)%,_%,$(if $(filter %$],$2),_)$(subst //,/_root_/,$(subst //,/,$(subst /../,/_../,$(subst /./,/_./,$(subst /_,/__,$(subst /,//,/$4))))))),$(call _outBX,$2))
_outBasis = $(if $(filter $5,$2),$(_outBS),$(call _outBS,$1$(subst _$(or $5,|),_|,_$2),$(or $5,out),$3,$4))

ifndef minion_start
  $(eval $(value _epilogue))
else
  minion_end = $(eval $(value _epilogue))
endif
