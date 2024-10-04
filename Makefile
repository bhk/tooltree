# Build (and test) tooltree packages

Alias(default).in = Alias(imports)
Alias(clean).in = Alias(clean-imports)

this-package = tooltree
package.tooltree.imports = smark webdemo mdb

include build/tooltree.mk

