# Minion builder classes for working with Lua sources
#
#    LuaRun, LuaTest, LuaExec : execute Lua scripts
#    LuaExe, LuaToC, LuaToLua : bundle Lua scripts with dependencies
#

# BuildLua: mixin that describes external dependencies fo this makefile.
#
BuildLua.inherit = _BuildLua
_BuildLua.luaExe = $(lua-exports)/bin/lua
_BuildLua.luaLib = $(lua-exports)/lib/liblua.lib
_BuildLua.luaIncludes = $(lua-exports)/src
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
_LuaEnv.preloadOpts  = $(addprefix -l ,{preloads})


# LuaRun(SOURCE) : Execute Lua SOURCE.
# LuaTest(SOURCE) : Execute Lua SOURCE, creating OK file on success.
# LuaExec(SOURCE) : Execute Lua SOURCE, capturing output.
#
LuaRun.inherit = LuaCmd Run
LuaExec.inherit = LuaCmd Exec
LuaTest.inherit = LuaCmd Test

LuaCmd.inherit  = _LuaCmd
_LuaCmd.inherit = LuaEnv
_LuaCmd.exec = {luaExe} {preloadOpts} {^} {execArgs}
_LuaCmd.up = {luaExe}


# LuaToC(SOURCES) : Bundle Lua SOURCES with all their dependencies in a
#    single C file.
#
LuaToC.inherit = _LuaToC
_LuaToC.inherit = LuaEnv Builder
_LuaToC.outExt = .c
_LuaToC.command = {exportPrefix} {luaExe} {cfromlua} -o {@} {flags} $(addprefix -l ,{preloads}) -MF {depsFile} -MP -Werror $(foreach l,{openLibs},--open=$l) -- {^}
_LuaToC.up = {luaExe} {cfromlua}
_LuaToC.depsFile = {@}.d
_LuaToC.flags = --minify
# openLibs = C extensions to be opened prior to the Lua modules being run
_LuaToC.openLibs =


# LuaToLua(SOURCES): generate a single Lua file that bundles a Lua file with
#    all of its dependencies.
#
LuaToLua.inherit = _LuaToLua
_LuaToLua.inherit = LuaToC
_LuaToLua.ext = .lua
_LuaToLua.flags = --luaout {inherit}


# LuaCC(...) : Variant of CC for building C sources that depend on
#    Lua headers.  `no-overlength-strings` is important to accommodate
#    cfromlua-generated C sources.
#
LuaCC.inherit = _LuaCC
_LuaCC.inherit = CC BuildLua
_LuaCC.includes = {luaIncludes} {inherit}
_LuaCC.stdFlags = {inherit} -Wno-overlength-strings


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
_LuaExe.inherit = BuildLua Exe
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
# execited.  A depsFile is written as a side effect.
_LuaExe.command = {inherit} $$( {luaExe} {cfromlua} --readlibs -MF {depsFile} -MT {@} -MP $(call get,out,{mainC}) )
_LuaExe.depsFile = {@}.d