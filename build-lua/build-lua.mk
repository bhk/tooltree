# Minion builder classes for working with Lua sources
#
#    LuaRun, LuaTest, LuaExec : execute Lua scripts
#    LuaExe, LuaToC, LuaBundle : bundle Lua scripts with dependencies
#

# BuildLua: mixin that describes external dependencies fo this makefile.
#
BuildLua.inherit = _BuildLua
_BuildLua.luaExe = $(package.lua)/bin/lua
_BuildLua.luaLib = $(package.lua)/lib/liblua.lib
_BuildLua.luaIncludes = $(package.lua)/src
_BuildLua.cfromlua := $(dir $(lastword $(MAKEFILE_LIST)))cfromlua.lua


# LuaEnv: mixin for defining properties related to the Lua interpreter
#   run-time environment.  These are also used by cfromlua (LuaToExe,...).
#   If you are building C Lua extensions, add them to `luaCPathLibs`.
#
LuaEnv.inherit = _LuaEnv BuildLua
_LuaEnv.exports = LUA_PATH LUA_CPATH {inherit}
_LuaEnv.LUA_PATH = $(subst $(\s),;,$(call _uniq,$(foreach d,{luaPathDirs},$(d:%/=%)/?.lua)))
_LuaEnv.LUA_CPATH = $(subst $(\s),;,$(call _uniq,$(foreach d,{luaCPathDirs},$(d:%/=%)/?.so)))
_LuaEnv.luaPathDirs = .
_LuaEnv.luaCPathDirs = {luaPathDirs} $(call _uniq,$(dir $(call get,out,{luaCPathLibs))))
_LuaEnv.luaCPathLibs =
_LuaEnv.deps = {inherit} {luaCPathLibs}
_LuaEnv.preloads =
_LuaEnv.preloadOpts = $(addprefix -l ,{preloads})


# LuaRun(SOURCE) : Execute Lua SOURCE.
# LuaExec(SOURCE) : Execute Lua SOURCE, capturing output.
#
LuaRun.inherit = LuaCmd Run
LuaExec.inherit = LuaCmd Exec

LuaCmd.inherit = _LuaCmd
_LuaCmd.inherit = LuaEnv
_LuaCmd.exec = {luaExe} {preloadOpts} {^} {execArgs}
_LuaCmd.up = {luaExe}


# LuaToC(SOURCES) : Bundle Lua SOURCES with all their dependencies in a
#    single C file.
#
LuaToC.inherit = _LuaToC
_LuaToC.inherit = LuaEnv Builder
_LuaToC.outExt = .c
_LuaToC.command = {exportPrefix} {luaExe} {cfromlua} -o {@} {flags} $(addprefix -l ,{preloads}) -MF {depsMF} -MP -Werror $(foreach l,{openLibs},--open=$l) -- {^}
_LuaToC.up = {luaExe} {cfromlua}
_LuaToC.depsMF = {outBasis}.d
_LuaToC.flags = --minify
# openLibs = C extensions to be opened prior to the Lua modules being run
_LuaToC.openLibs =


# LuaBundle(SOURCES): generate a single Lua file that bundles a Lua file with
#    all of its dependencies.
#
LuaBundle.inherit = _LuaBundle
_LuaBundle.inherit = LuaToC
_LuaBundle.outExt = .lua
_LuaBundle.flags = --luaout {inherit}


# LuaCC(...) : Variant of CC for building C sources that depend on
#    Lua headers.  `no-overlength-strings` is important to accommodate
#    cfromlua-generated C sources.
#
LuaCC.inherit = _LuaCC
_LuaCC.inherit = CC BuildLua
_LuaCC.includes = {luaIncludes} {inherit}
_LuaCC.srcFlags = {inherit} -Wno-overlength-strings


# LuaLib(SOURCES/OBJECTS): like `Lib`, but LuaCC is used.
#
LuaLib.inherit = Lib
LuaLib.inferClasses = LuaCC.c


# LuaSharedLib(SOURCES/OBJECTS): like `Lib`, but LuaCC is used.
#
LuaSharedLib.inherit = SharedLib
LuaSharedLib.inferClasses = LuaCC.c


# LuaExe(LUASOURCES): build an executable with the Lua interpreter, named
#    scripts, and their dependencies (scripts & C extensions). This works
#    much like `Exe` except that one or more Lua sources are included
#    along with object files.
#
#    Implementation notes:
#
#    - All Lua sources in {in} are passed to a single LuaToCC() instance to
#      generate the "main" C file.  Other inputs are assumed to be .c or .o.
#    - Compile the main C source and other .c inputs using LuaCC(...).
#    - Link the compiled objects with lualib and other discovered libraries.
#
LuaExe.inherit = _LuaExe
_LuaExe.inherit = BuildLua CExe
_LuaExe.up = {luaExe} {cfromlua}

# Classes used used for bundling and compilation can be overridden:
_LuaExe.ccClass = LuaCC
_LuaExe.l2cClass = LuaToC

# Pass all arguments through to LuaToC to generate a single C file.
_LuaExe.inX = $(call _expand,{in},in)
_LuaExe.mainC = {l2cClass}($(subst $(\s),$;,$(filter %.lua,{inX})))
_LuaExe.inIDs = {ccClass}({mainC}) {luaLib} $(patsubst %.c,{ccClass}(%.c),$(filter-out %.lua,{inX}))
_LuaExe.inPairs = $(foreach i,{inIDs},$i$(if $(filter %$],$i),$$$(call get,out,$i)))

# We need to include *discovered* libraries on the link command line, but we
# don't know them at rule generation time, so we use the `$(...)` shell
# construct to extract them from the generated C file when this command is
# execited.  A depsMF is written as a side effect.
_LuaExe.command = {inherit} $$( {luaExe} {cfromlua} --readlibs -MF {depsMF} -MT {@} -MP $(call get,out,{mainC}) )
_LuaExe.depsMF = {outBasis}.d


# LuaTest(SOURCE) : Execute Lua SOURCE, creating OK file on success.
#
LuaTest.inherit = _LuaTest
_LuaTest.inherit = LuaCmd Test
_LuaTest.scanID = LuaScan($(word 1,{inIDs}))
# oo = LuaTest(TEST_FOR_X) where X is an implicit dependency.
_LuaTest.oo = $(filter-out $(_self),\
   $(patsubst %,$(_class)(%),\
      $(call {getTest_fn},$(call get,dependencies,{scanID}))))
# When implicit dependencies change, {scanID}.out will be updated.
_LuaTest.deps = {inherit} {scanID}
# Override {getTest_fn} for different convention for test file naming.
_LuaTest.getTest_fn = _LuaTest_getTest

# Return unit tests for dependencies listed in $1. [Note that this is not a
#   property, so it cannot use {PROP} syntax, but it can use $(call .,PROP)
#   because it is evaulated in the context of a property definition.]
_LuaTest_getTest ?= $(wildcard $(patsubst %.lua,%_q.lua,%(filter %.lua,$1)))


# LuaScan(SOURCE): output the implicit dependencies of Lua file SOURCE.
#
#    {dependencies} gives the dependencies described in {out}, using Make's
#    `include` directive, but since properties are evaulated *before* any
#    rules are executed, this property reflects the dependencies as of the
#    previous invocation of Make!
#
#    Due to a feature in GNU Make, when an included file is stale (i.e. it
#    is the target of a rule that needs to be updated) all other rules are
#    ignored, the stale include file targets are updated, and then the
#    entire makefile is re-invoked.  Therefore, when a Lua source file is
#    changed, all affected LuaScan() outputs will be invalid, and their rules
#    will be re-run.  On the subsequent (automatic) re-invocation of Make,
#    the LuaScan outputs will be valid and {dependencies} will be up to date.
#
LuaScan.inherit = _LuaScan
_LuaScan.inherit = LuaEnv Builder
_LuaScan.outExt = .mk
_LuaScan.command = {exportPrefix} {luaExe} {cfromlua} -MF {@} -Mfmt '$(_self)_scan = %s' -- {<}
_LuaScan.dependencies = $(call _eval,-include {@})$($(_self)_scan,$(_self))
_LuaScan.deps = {dependencies}
