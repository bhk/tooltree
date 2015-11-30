include .config
include $(crank)/crank.min

VFile = $(call v.,buildDir)/crank-lua.min
VFile.parent = Snip
VFile.out = $I
VFile.deps := $(firstword $(MAKEFILE_LIST))
#------------------------------------------------------------------------
define VFile.data
crank-lua.lua = $(lua)
crank-lua.luaHost = $(luaHost)
crank-lua.crank-c = $(crank-c)

include $$(<dirname>)/$(call <relpath>,$(call v.,buildDir),.)/crank-lua.min

endef
#------------------------------------------------------------------------


Phony = test_all test_clean

Phony[test_all].command = $(MAKE) -C test --print-directory V='$v'
Phony[test_all].deps = $(call get*,out,VFile)
Phony[test_all].prereqOf = all

Phony[test_clean].command = rm -rf test/.crank test/out
Phony[test_clean].prereqOf = clean

$(build)
