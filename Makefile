#--------------------------------
# Project = packages to build
#
# This is in the format of a package `deps` variable. The project itself can
# be thought of as a package named `all` that lists these dependencies.

Project = smark webdemo mdb


#--------------------------------
# Variants = variants (of the project) to build
#
# Each project variant usually builds the same variant of each dependency
# listed in $(Project), but not always:
#
#    1. The dependency in $(Project) may include an explicit query string,
#       in which case it will not inherit the project's variant.
#
#    2. The dependency's Package file may specify some other `v` instead
#       of using the query string.

Variants ?= $(V.default) # gcc llvm arm android


#--------------------------------
# Package properties

# The `dir` property gives the root directory for package $I

Package.dir = $(wildcard $I opensource/$I)


#--------------------------------
# Variant properties

# `.host` is the variant to use for tools
V.host = $(firstword $(filter $(V.default) gcc llvm,$(Variants)) $(V.default))


V[android].skipTests = true
V[android].c-targetOS = Linux

#--------------------------------
customRules = smoke uberclean allclean
include crank/project.mak

smoke: uberclean
	make configure Project='cdep ctools mdb p4x pakman smark pages webdemo' Variants='$(V.default) gcc'
	make -j12

uberclean:
	git clean -xdf

allclean:
	rm -rf .built */.crank/ */out/
