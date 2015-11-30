include .config
include $(crank)/crank.min

# Re-export our dependencies for clients to use...

VFile = $(call v.,buildDir)/crank-c.min
VFile.parent = Snip
VFile.out = $I
VFile.deps := $(firstword $(MAKEFILE_LIST))
#----------------------------------------------------------------
define VFile.data
crank-c.dir := $$(call <cleanPath>,$$(<dirname>)/$(call <relpath>,$(call v.,buildDir),.))
crank-c.ctools = $(if $(ctools),$$(call <cleanPath>,$$(crank-c.dir)/$(ctools)),$$(error .crank-c.min: ctools not configured as a dependency))
crank-c.cdep = $(if $(cdep),$$(call <cleanPath>,$$(crank-c.dir)/$(cdep)/cdep),$$(error .crank-c.min: cdep not configured for uname="$(<uname>)"))
crank-c.coverage = $(if $(ctools),1)

include $$(crank-c.dir)/crank-c.min

endef
#----------------------------------------------------------------


Phony = test_all test_clean

Phony[test_all].command = $(MAKE) -C test --print-directory V='$v'
Phony[test_all].deps = $(call get*,out,VFile)
Phony[test_all].prereqOf = all

Phony[test_clean].command = rm -rf test/$(call v.,buildDir)
Phony[test_clean].prereqOf = clean

$(build)
