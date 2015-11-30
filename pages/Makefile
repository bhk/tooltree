include .config
include $(crank)/crank.min
include $(smarkResult)/crank-smark.min


Pages.parent = SmarkDoc
Pages.out = $(call v.,buildDir)/$(call .,name).html
Pages.name = $(basename $(notdir $I))
Pages.css = pages.css

Pages += index.txt \
         $(smark)/smark.txt \
         $(pakman)/UsersGuide.txt \
         $(crank)/crank.txt \
         $(crank)/project.txt \
         $(wildcard $(monoglot)/*.txt) \
         $(wildcard $(luau)/*.txt) \
         $(wildcard $(jsu)/*.txt) \
         $(mdb)/mdb.txt \
         $(crank-lua)/crank-lua.txt \
         $(crank-lua)/cfromlua.txt \
         $(crank-js)/crank-js.txt \
         $(crank-lua)/cfromlua.txt \

Pages[$(pakman)/UsersGuide.txt].name = pakman


# To deploy to a repo that has the gh-pages branch checked out, type `make`
# when `Deploy.dir` is set to the path to the repo.  It can be defined on the
# make command line or in .userconfig [see crank/project.txt]
#

# To commit the deployed changes, type `make Commit` with `Deploy.dir` defined.

ifdef Deploy.dir
  Deploy.parent = Copy
  Deploy = $(call get*,out,Pages)

  Commit.parent = Gen
  Commit.prereqOf = # name `Commit` explicitly on the command line
  Commit.command = cd $(Deploy.dir) && git add . && git diff --cached --stat && printf 'Commit? ' && ( head -1 | grep [yY] > /dev/null && git commit -m '-' && git push || echo Nothing pushed)
  Commit.deps = $(call get*,out,$I)
  Commit.in =
  Commit += Deploy
endif

$(build)
