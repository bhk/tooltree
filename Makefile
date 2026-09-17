# Build (and test) tooltree packages

default = Package@top
clean = Clean(default)

top = smark webdemo mdb pages

include build/tooltree.mk
