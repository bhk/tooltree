# External dependencies
include .config
include $(crank)/crank.min
include $(crank-lua)/crank-lua.min
include $(crank-js)/crank-js.min

# GNU make bug: when exporting a target-specific PATH variable, it will
# not be in effect when PATH is searched for the executed command.
export LUA = $(call v.,c-emulator) $(lua)/bin/lua


# JavaScript

JSEnv.nodePathDirs = . $(jsu)

JSToHTML += $(wildcard *_demo.js) mdbapp.js
JSTest += $(filter-out ui_q.js,$(wildcard *_q.js))


GZip.parent = Gen
GZip.ext = $(suffix $<).gz
GZip.command = gzip -c $^ > $@ || (rm -f $@ ; false )

GZip += $(call get,out,JSToHTML,mdbapp.js)


# Lua

# lpeg is an indirect dependency
LuaEnv.luaPathDirs = . $(luau) $(monoglot) $(lpeg)
LuaEnv.exports += REQUIREFILE_PATH
LuaEnv.REQUIREFILE_PATH = $(subst $(\s),;,$(call <uniq>,$(call get*,dir,JSToHTML GZip)))
LuaEnv.deps = $(call inherit)
LuaEnv.ooDeps = $(call get*,out,JSToHTML)

LuaTest += $(wildcard *_q.lua)
LuaExe += mdb.lua
LuaToLua += mdbagent.lua


# Run MDB (or other server) as a script
#    make run_mdb [example=a/b/c] [serve=mdb_demo]
#    make run_owebtest

Run += mdb.lua owebtest.lua

Run.parent = LuaRun
Run.out = run_$(basename $I)
Run.ooDeps = $(call get*,out,LuaTest JSTest) $(call get*,out,GZip)
Run.args = $(if $(noui),,--ui) $(call .,serveArg)
Run.prereqOf =
Run.command = $(LUA) $(call .,in) $(call .,args)
Run.exports = $(call inherit) SERVEDIR
Run.SERVEDIR = $(call get,dir,JSToHTML,$(firstword $(JSToHTML)))
Run.serveArg = $(if $(serve),--uri=serve/$(serve).html)
Run[mdb.lua].args      = $(call inherit) -- $(call .,luaExe) mdbagent.lua $(call .,example)
Run[mdb.lua].example   = $(or $(call <assoc>,$(or $(example),a),a=example.lua b=../webdemo/demo.lua c=mdb.lua),$(example))
Run[owebtest.lua].args = $(call inherit) $(call get,out,JSToHTML,oweb_demo.js)


Phony += size
Phony[size].command = make JSBundle=mdbapp.js && uglifyjs $(call get,out,JSBundle,mdbapp.js) -c -m | wc


Ship/bin.parent = Copy
Ship/bin.dir = out/$v/bin
Ship/bin = $(call get*,out,LuaExe)

Ship/src.parent = Copy
Ship/src.dir = out/$v/src
Ship/src = $(call get*,out,LuaToLua)


$(build)
