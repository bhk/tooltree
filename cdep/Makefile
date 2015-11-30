include .config
include $(crank)/crank.min
include $(crank-c)/crank-c.min

# Build cdep exe
Exe = cdep

# The Compile class uses cdep in Windows builds.  To build cdep without cdep
# we hardcode conservative deps.
Compile.depCmd = true
Compile.deps = $(wildcard *.c* *.h*)


# cdep tests: the name of each .out file describes the command that produces it.
CDTest         += $(if $(call v.,c-noExec),,$(wildcard test/cdep_*.out))

CDTest.parent  = ExeTest
CDTest.exe     = $(call get,out,Exe,cdep)
CDTest.deps    = $I
CDTest.tmpFile = $(basename $@).out
CDTest.args    = $(subst @,/,$(wordlist 2,99,$(subst _, ,$(basename $I))))
CDTest.test    = $(call inherit) $(call .,fixCR) > $(call .,tmpFile) && cmp -s $(call .,tmpFile) $^
CDTest.fail    = echo "==== Expected:" ; cat $^ ; echo "==== Saw:" ; cat $(call .,tmpFile)

# for coverage, build a "cov" variant and `make Coverage=cdep.c`
Coverage.classes += CDTest

# normalize line endings on Windows by removing carriage returns
CDTest.fixCR    = $(if $(filter Win%,$(<uname>)),| tr -d '\r')

# Deploy result
Ship.parent = Copy
Ship.dir  = out/$v
Ship.deps = $(call get*,out,CDTest)
Ship = $(call get*,out,Exe)

$(build)
