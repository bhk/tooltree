# Build (and test) tooltree packages

MAKEFLAGS := -j9

Alias(default).in = Package@project
Alias(clean_all).in = CleanPackage@project

project = smark webdemo mdb

include build/tooltree.mk
