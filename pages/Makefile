# Default target builds all HTML files into $(VOUTDIR).
# make deploy [DEPLOYDIR=...] : Copy files to DEPLOYDIR and add them to git
#
Alias(default).in = @htmlFiles
Alias(deploy).in = Deploy(@htmlFiles)

htmlFiles = SmarkDoc@docs
docs = index.txt \
  $(filter-out %/todo.txt,\
    $(wildcard $(foreach P,$(docPackages),$(package.$P.dir)*.txt)))
docPackages = build build-js build-lua jsu luau mdb monoglot smark

# put them all in the same directory for ease of viewing
SmarkDoc.outDir = $(VOUTDIR)
SmarkDoc.css = pages.css

Deploy.inherit = Phony
Deploy.in = $(patsubst %,Copy(%,dir:{toDir}/),$(wildcard .out/*.html))
Deploy.toDir = $(or $(DEPLOYDIR),\
   $(error DEPLOYDIR variable must be set by user for 'make deploy'))
Deploy.command = \
  cd {toDir} && git add . && git diff --cached --stat && printf 'Commit? ' &&\
  ( head -1 | grep [yY] > /dev/null && git commit -m '-' && git push || \
    echo Nothing pushed)

includeImports = smark/smark.mk
include ../build/tooltree.mk
