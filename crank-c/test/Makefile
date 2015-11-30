include .config

# use $(crank-c) as if we were an ordinary client of crank-c
crank-c = ../$(call v.,buildDir)

include $(crank)/crank.min
include $(crank-c)/crank-c.min

#--------------------------------
# Build and test and executable with C and C++ sources.

Exe = hello
Exe[hello].in = hello.c foo.cpp

Compile[hello.c].std = gnu99

# avoid dependency on cdep
Compile.cdep = true

# run generated executable
CCTest.parent = ExeTest
CCTest.test = $(call inherit)

CCTest += $(call get,out,Exe,hello)


ifneq "" "$(crank-c.coverage)"
  CovTest += $(call get*,out,CCTest)
  CovTest.parent = Test
  CovTest.command = grep 'foo\.cpp' $I > /dev/null
endif


$(build)
