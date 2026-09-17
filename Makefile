# Build (and test) tooltree packages

default = imports
clean = Clean(imports)

thisPackage = tooltree
package.tooltree.imports = smark webdemo mdb pages

include build/tooltree.mk

