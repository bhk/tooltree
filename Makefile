# Build (and test) tooltree packages

Alias(default).in = Package@project
Alias(clean).in = CleanPackage@project

project = smark webdemo mdb

include build/tooltree.mk

