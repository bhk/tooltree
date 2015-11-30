include .config
include $(crank)/crank.min

Phony += a b

a.command = echo "$${AVAR}_$v"
a.exports = AVAR
a.AVAR = A

b.deps = $(call get,out,Phony,a)
b.command = echo "B_$v"

$(build)
