# Minion builder classes for working with JS sources
#
#    JSBundle, JSToHMTL: bundle a JS file with its dependencies
#    JSTest: run tests on JS files
#
# Imported variables:
#    

# BuildJS: mixin that describes external dependencies of this makefile.
#
BuildJS.inherit = _BuildJS
_BuildJS.jsdepExe := $(dir $(lastword $(MAKEFILE_LIST)))jsdep
_BuildJS.node = $(or $(firstword $(shell which nodejs node)),$(error "node not in path!"))


# JSEnv: mixin that describes the environment for running Node
#
JSEnv.inherit = _JSEnv BuildJS
_JSEnv.exports = {inherit} NODE_PATH
_JSEnv.NODE_PATH = $(subst $(\s),:,{nodePathDirs})
_JSEnv.nodePathDirs = .


# JSBundle(JSSOURCE): bundle source & its dependencies into one source file
#
JSBundle.inherit = _JSBundle
_JSBundle.inherit = JSEnv Builder
_JSBundle.outExt = .js
_JSBundle.command = {exportPrefix} {jsdepExe} {flags} -o {@} --odep={depsMF} {<}
_JSBundle.up = {jsdepExe}
_JSBundle.flags = --bundle
_JSBundle.depsMF = {outBasis}.d


# JSToHTML(JSSOURCE): bundle source & its dependencies into an HTML file
#
JSToHTML.inherit = _JSToHTML
_JSToHTML.inherit = JSBundle
_JSToHTML.outExt = .html
_JSToHTML.flags = --html


# JSTest(TEST): Execute JavaScript source file TEST.
#
#    Other JS sources loaded by TEST will be identified, and if there are
#    tests for those tests will be marked as strict dependencies so that
#    those tests will be executed before this test.  Testing sources are
#    identified using the {getTest_fn} function.
#
JSTest.inherit = _JSTest
_JSTest.inherit = JSEnv Test
_JSTest.exec = {node} {execArgs} {^}
_JSTest.scanID = JSScan($(word 1,{inIDs}))
# oo = JSTest(TEST_FOR_X) where X is an implicit dependency.
_JSTest.oo = $(filter-out $(_self),\
   $(patsubst %,$(_class)(%),\
      $(call {getTest_fn},$(call get,dependencies,{scanID}))))
# When implicit dependencies change, {scanID}.out will be updated.
_JSTest.deps = {scanID}
# Override {getTest_fn} for different convention for test file naming.
_JSTest.getTest_fn = _JSTest_getTest

# Return unit tests for dependencies listed in $1. [Note that this is not a
#   property, so it cannot use {PROP} syntax, but it can use $(call .,PROP)
#   because it is evaulated in the context of a property definition.]
_JSTest_getTest ?= $(wildcard $(patsubst %.js,%_q.js,$(filter %.js,$1)))


# JSScan(SOURCE): output the implicit dependencies of JavaScript file SOURCE.
#
#    {dependencies} gives the dependencies described in {out}, using Make's
#    `include` directive, but since properties are evaulated *before* any
#    rules are executed, this property reflects the dependencies as of the
#    previous invocation of Make!
#
#    Due to a feature in GNU Make, when an included file is stale (i.e. it
#    is the target of a rule that needs to be updated) all other rules are
#    ignored, the stale include file targets are updated, and then the
#    entire makefile is re-invoked.  Therefore, when a JS source file is
#    changed, all affected JSScan() outputs will be invalid, and their rules
#    will be re-run.  On the subsequent (automatic) re-invocation of Make,
#    the JSScan outputs will be valid and {dependencies} will be up to date.
#
JSScan.inherit = _JSScan
_JSScan.inherit = JSEnv Builder
_JSScan.outExt = .mk
_JSScan.command = {exportPrefix} {jsdepExe} -o {@} --format='$(_self)_scan = %s' {<}
_JSScan.dependencies = $(call _eval,-include {@})$($(_self)_scan,$(_self))
_JSScan.deps = {dependencies}
