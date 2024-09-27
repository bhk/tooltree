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
_JSBundle.command = {jsdepExe} {flags} -o {@} --odep={depsFile} {<}
_JSBundle.up = {jsdepExe}
_JSBundle.flags = --bundle
_JSBundle.depFile = {@}.d


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
_JSTest.ID1 = $(word 1,{inIDs}}

# Test dependencies before running this rule
_JSTest.oo = $(filter-out $(_self),$(patsubst %,$(_class)(%),$(call {getTest_fn},{requiredFiles})))
_JSTest.getTest_fn = _JSTest_getTest
_JSTest.requiredFiles = $(call get,requiredFiles,JSTestScan({ID1}))
_JSTest.deps = JSTestScan({ID1})

# Get souce files that test $1
_JSTest_getTest ?= $(wildcard $(patsubst %.js,%_q.js,$1))


# JSTestScan(SOURCE): scan implied dependencies of JavaScript file SOURCE,
#    and write them to a Make include file.  The `requiredFiles` property --
#    evaluated in the rule-generation phease -- includes this output file
#    using Make's `include` directive.
#
#    Due to a feature in GNU Make, when an included file is stale (needs to
#    be update during the rule execution phase) all other rules are ignored
#    and the included file(s) are updated, and then the entire makefile is
#    restarted.  The value of the `requiredFiles` property, therefore, can
#    be treated as up-to-date.
#
JSTestScan.inherit = _JSTestScan
_JSTestScan.inherit = JSEnv Builder
#? _JSTestScan.depsFor = $(call get,out,JSTest,$I)
_JSTestScan.outExt = .deps
_JSTestScan.command = {jsdepExe} -o {@} --format='JSTestScan($(_argText)).scan = %s' {<}
_JSTestScan.scan =
_JSTestScan.requiredFiles = $(call _eval,-include {@}){scan}
_JSTestScan.deps = {requiredFiles}
