# Default target builds all HTML files into $(VOUTDIR).
# make deploy [DEPLOYDIR=...] : Copy files to DEPLOYDIR and add them to git
#
Alias(default).in = @htmlFiles
Alias(deploy).in = Deploy(@htmlFiles)

htmlFiles = SmarkDoc@docs
docPackages = $(package.pages.imports)
docs = index.txt $(wildcard $(foreach P,$(docPackages),$(package.$P)/*.txt))

# put them all in the same directory for ease of viewing
SmarkDoc.outDir = $(VOUTDIR)
SmarkDoc.css = pages.css

Deploy.inherit = Phony
Deploy.in = $(foreach a,$(call _expand,$(_args)),Copy($a,dir:{toDir}/))
Deploy.toDir = $(or $(DEPLOYDIR),\
   $(error DEPLOYDIR variable must be set by user for 'make deploy'))
Deploy.command = \
  cd {toDir} && git add . && git diff --cached --stat && printf 'Commit? ' &&\
  ( head -1 | grep [yY] > /dev/null && git commit -m '-' && git push || \
    echo Nothing pushed)

includeImports = smark/smark.mk
include ../build/tooltree.mk
