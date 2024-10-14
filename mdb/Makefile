# make [default] : build & ship mdb executable & mdbagent.lua
# make 'Demo(X)' : create HTML from X_demo.js & open it in a browser
# make mdb / mdblua : run MDB executable / sources with sample debug target
#   make ... serve=mdb_demo : use primtive state inspector for UI
#   make ... example=... : select debug target (a, b, c, or specific file)
# make owebtest : run owebtest
# make size : compute size of JS bundled in MDB

Alias(default).in = Ship(exports) LuaTest@*_q.lua JSTest@*_q.js
Alias(mdb).in = RunMDB(LuaExe(mdb.lua))
Alias(mdblua).in = LuaRunMDB(mdb.lua)
Alias(owebtest).in = LuaRun(owebtest.lua)
Alias(size).in = JSBundle(mdbapp.js)
Alias(size).command = uglifyjs $(call get,out,{in}) -c -m | wc

exports = LuaExe(mdb.lua) LuaBundle(mdbagent.lua) mdb.txt

Demo.inherit = Phony
Demo.in = JSToHTML({inherit}_demo.js)
Demo.command = open {<}

# Run mdb executable.  We include LuaEnv for env vars needed by the Lua
#    interpreter child process, which needs to run mdbagent.lua.
RunMDB.inherit = MDB LuaEnv Run

# Run mdb.lua
LuaRunMDB.inherit = MDB LuaRun

# JS & Lua environments (for xxTest, xxRun, xxBundle, xxExe rules)
JSEnv.nodePathDirs = . $(package.jsu)
LuaEnv.luaPathDirs = . $(package.luau) $(package.monoglot) $(package.lpeg)
LuaEnv.exports = {inherit} OUTDIR $(LuaEnv_$(_argText)_exports)
LuaEnv.OUTDIR = $(VOUTDIR)
LuaEnv.deps = {inherit} $(LuaEnv_$(_argText)_deps)

# mdb.lua reads $(mdbJS) using `requirefile` ==> customize exports and deps.
#   We do this at the LuaEnv level to cover LuaRun *and* LuaExe behavior.
#   We use "..._PROP" variables for instance customization (see
#   LuaEnv.exports, above).  Note that these are not property definitions,
#   they are just Make variables, so {...} syntax is unsupported.
mdbJS = GZip(JSToHTML(mdbapp.js))
LuaEnv_mdb.lua_exports = REQUIREFILE_PATH
LuaEnv_mdb.lua_deps = $(mdbJS)
LuaEnv.REQUIREFILE_PATH = $(dir $(call get,out,$(mdbJS)))

# MDB mixin defines properties for executing MDB via either LuaRun or Run
MDB.execArgs = --ui {uriArg} -- {luaExe} mdbagent.lua {exampleArg}
MDB.exampleArg = $(word 2,$(subst =, ,\
  $(filter $(example)%,a=example.lua b=../webdemo/demo.lua c=mdb.lua $(example)=$(example))))
MDB.uriArg = $(if $(serve),--uri='serve/$(call get,out,JSToHTML($(serve).js))')
MDB.deps = {inherit} $(if $(serve),JSToHTML($(serve).js))

# target_q.lua needs LUA environment variable
LuaEnv_target_q.lua_exports = LUA
LuaEnv.LUA = {luaExe}

LuaRun(owebtest.lua).in = owebtest.lua JSToHTML(oweb_demo.js)

minionCache = default

includeImports = build-lua/build-lua.mk build-js/build-js.mk
include ../build/tooltree.mk
