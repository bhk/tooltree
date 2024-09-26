# Minion builder classes for working with Lua sources
#
#    LuaRun, LuaTest, LuaExec : execute Lua scripts
#    LuaExe, LuaToC, LuaToLua : bundle Lua scripts with dependencies
#

# Imports.  To configure, override these or define `luaExports`.
#
BuildLua.inherit       = _BuildLua
_BuildLua.luaExe       = $(lua-exports)/bin/lua
_BuildLua.luaLib       = $(lua-exports)/lib/liblua.lib
_BuildLua.luaIncludes  = $(lua-exports)/src
_BuildLua.cfromlua    := $(dir $(lastword $(MAKEFILE_LIST)))cfromlua.lua


# LuaEnv: mixin for defining properties related to the Lua interpreter
#   run-time environment.  These are also used by cfromlua (LuaToExe,...).
#
LuaEnv.inherit       = _LuaEnv BuildLua
_LuaEnv.exports      = LUA_PATH LUA_CPATH {inherit}
_LuaEnv.LUA_PATH     = $(subst $(\s),;,$(call <uniq>,$(foreach d,{luaPathDirs},$(d:%/=%)/?.lua)))
_LuaEnv.LUA_CPATH    = $(subst $(\s),;,$(call <uniq>,$(foreach d,{luaCPathDirs},$(d:%/=%)/?.so)))
_LuaEnv.luaPathDirs  = .
_LuaEnv.luaCPathDirs = {luaPathDirs}
_LuaEnv.preloads     =
_LuaEnv.preloadOpts  = $(addprefix -l ,{preloads})


# LuaRun(SOURCE) : Execute Lua SOURCE.
# LuaTest(SOURCE) : Execute Lua SOURCE, creating OK file on success.
# LuaExec(SOURCE) : Execute Lua SOURCE, capturing output.
#
LuaRun.inherit  = LuaCmd Run
LuaExec.inherit = LuaCmd Exec
LuaTest.inherit = LuaCmd Test

LuaCmd.inherit  = _LuaCmd
_LuaCmd.inherit = BuildLua LuaEnv
_LuaCmd.exec    = {luaExe} {preloadOpts} {^} {execArgs}
_LuaCmd.up      = {luaExe}


# LuaCC(...) : Variant of CC for building Lua C extension sources
#
LuaCC.inherit  = _LuaCC
_LuaCC.inherit  = CC BuildLua
_LuaCC.includes = {luaIncludes} {inherit}
_LuaCC.stdFlags = {inherit} -Wno-overlength-strings


# LuaExe(LUASOURCES): build an executable with the Lua interpreter, named
#    scripts, and their dependencies (scripts & C extensions). This works
#    much like `Exe` except that one or more Lua sources are included
#    along with object files.
#
# Implementation notes:
#
#   - LuaToC(...) generates a "main" C source from all Lua sources.
#   - Compile the main C source and other C file inputs using CC(...).
#   - Link the compiled objects with lualib and other discovered libraries.
#
LuaExe.inherit   = _LuaExe
_LuaExe.inherit  = Exe BuildLua
_LuaExe.up       = {luaExe} {cfromlua}

# The class used to bundle Lua sources to a C executable
_LuaExe.ccClass = LuaCC
# The class used to compile C files
_LuaExe.l2cClass = LuaToC

# Pass all arguments through to LuaToC to generate a single C file.
_LuaExe.inX = $(call _expand,{in},in)
_LuaExe.mainC = {l2cClass}($(subst $(\s),$;,$(filter %.lua,{inX})))
_LuaExe.inIDs = {ccClass}({mainC}) {luaLib} $(patsubst %.c,{ccClass}(%.c),$(filter-out %.lua,{inX}))
_LuaExe.inPairs = $(foreach i,{inIDs},$i$(if $(filter %$],$i),$$$(call get,out,$i)))

# The link command line invokes cfromlua using the `$(...)` shell construct
# to extract the list of discovered native extensions from the main C file,
# and to write their dependencies into a .d file.  (These are not known at
# Make rule generation time.)
_LuaExe.command = {inherit} $$( {luaExe} {cfromlua} --readlibs -MF {depsFile} -MT {@} -MP $(call get,out,{mainC}) )
_LuaExe.depsFile = {@}.d


# LuaToC(SOURCES) : Bundle Lua SOURCES with all their dependencies in a
#    single C file.
#
LuaToC.inherit   = LuaEnv _LuaToC
_LuaToC.inherit  = Exec
_LuaToC.outExt   = .c
_LuaToC.command  = {exportPrefix} {luaExe} {cfromlua} -o {@} {flags} $(addprefix -l ,{preloads}) -MF {depsFile} -MP -Werror $(foreach l,{openLibs},--open=$l) -- {^}
_LuaToC.up       = {luaExe} {cfromlua}
_LuaToC.depsFile = {@}.d
_LuaToC.flags    = --minify
# openLibs = C extensions to be opened prior to the Lua modules being run
_LuaToC.openLibs =


# LuaToLua(SOURCES): generate a single Lua file that bundles a Lua file with
#    all of its dependencies.
#
LuaToLua.inherit  = _LuaToLua
_LuaToLua.inherit = LuaToC
_LuaToLua.ext     = .lua
_LuaToLua.flags   = --luaout {inherit}
