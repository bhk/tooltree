# Minion builder classes for working with Lua sources
#
#    LuaRun, LuaTest, LuaExec : execute Lua scripts
#    LuaExe, LuaToC, LuaBundle : bundle Lua scripts with dependencies
#

# BuildLua: mixin that describes external dependencies of this makefile.
#
BuildLua.inherit = _BuildLua
_BuildLua.lua = $(call get,export,Package(lua))
_BuildLua.luaExe = {lua}/bin/lua
_BuildLua.luaLib = {lua}/lib/liblua.lib
_BuildLua.luaIncludes = {lua}/src
_BuildLua.cfromlua := $(dir $(lastword $(MAKEFILE_LIST)))cfromlua.lua


# LuaEnv: mixin for defining properties related to the Lua interpreter
#   run-time environment.  These are also used by cfromlua (LuaToExe,...).
#   If you are building C Lua extensions, add them to `luaCPathLibs`.
#
#   By default, this reflects imported packages that export luaPathDirs.
#
LuaEnv.inherit = _LuaEnv BuildLua
_LuaEnv.exports = LUA_PATH LUA_CPATH {inherit}
_LuaEnv.LUA_PATH = $(subst $(\s),;,$(call _unique,$(foreach d,{luaPathDirs},$(d:%/=%)/?.lua)))
_LuaEnv.LUA_CPATH = $(subst $(\s),;,$(call _unique,$(foreach d,{luaCPathDirs},$(d:%/=%)/?.so)))
_LuaEnv.packages = $(filter-out build-lua,$(_thisImports))
_LuaEnv.luaPathDirs = . $(call _getPackageExports,luaPathDirs,{packages})
_LuaEnv.luaCPathDirs = {luaPathDirs} $(call _unique,$(dir $(call get,out,{luaCPathLibs})))
_LuaEnv.luaCPathLibs =
_LuaEnv.deps = {luaCPathLibs} {inherit}
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
_LuaToC.up = {cfromlua} {inherit}
_LuaToC.depsMF = {outBasis}.d {inherit}
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
_LuaExe.mainC = {l2cClass}($(subst $(\s),$;,$(filter %.lua,{inX})))
_LuaExe.inIDs = {ccClass}({mainC}) {luaLib} $(patsubst %.c,{ccClass}(%.c),$(filter-out %.lua,{inX}))
_LuaExe.inPairs = $(foreach i,{inIDs},$i$(if $(filter %$],$i),$$$(call get,out,$i)))

# We need to include *discovered* libraries on the link command line, but we
# don't know them at rule generation time, so we use the `$(...)` shell
# construct to extract them from the generated C file when this command is
# execited.  A depsMF is written as a side effect.
_LuaExe.command = {inherit} $$( {luaExe} {cfromlua} --readlibs -MF {depsMF} -MT {@} -MP $(call get,out,{mainC}) )
_LuaExe.up = {luaExe} {cfromlua}
_LuaExe.depsMF = {outBasis}.d {inherit}


# LuaTest(SOURCE) : Execute Lua SOURCE, creating OK file on success.
#
LuaTest.inherit = _LuaTest
_LuaTest.inherit = LuaCmd Test
_LuaTest.deps = LuaScan($(_self)) {inherit}


# LuaScan(TESTID): scan Lua source implicit dependencies and generate an
#    include file naming those dependencies and OO deps on inferred tests.
#
#      TESTID.in = Lua source file
#      TESTID.out = output file that is target of the dependencies
#
#    We run this scan as a distinct Make rule -- versus in the same rule as
#    TESTID as with CC implied deps.  This is in order to discover test
#    order-only deps that would need to be known before the test rule is
#    invoked.  This will involve Make's auto-restart feature.
#
#    Note that this will not create rules for running lower-level tests;
#    it guesses test result file names using LuaTest() and outputs dummy
#    rules (a la gcc -MP) so that when those test rules don't actually
#    exist the dependency will be ignored.
#
LuaScan.inherit = _LuaScan
_LuaScan.inherit = LuaEnv Builder
_LuaScan.outExt = .d
_LuaScan.luaSource = $(call get,<,$(_arg1))
# To work around tooltree/build/makebug.mk, we omit {luaSource} from this
# rule's prereqs and rely on the generated file to name that dependency.
_LuaScan.in = 
_LuaScan.command = {exportPrefix} {luaExe} {cfromlua} {luaSource} -MF {@} -Moo {Moo} -MT {MT} -MTF -MP
_LuaScan.up = {luaExe} {cfromlua}
_LuaScan.MT = $(call get,out,$(_arg1))
_LuaScan.Moo = $(call get,out,LuaTest(^B_q.lua))
_LuaScan.rule = {inherit}-include {@}$(\n)
