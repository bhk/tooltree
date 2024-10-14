# Build (and test) tooltree packages

Alias(default).in = Alias(imports)
Alias(clean).in = Clean(Alias(imports))

thisPackage = tooltree
package.tooltree.imports = smark webdemo mdb pages

include build/tooltree.mk

