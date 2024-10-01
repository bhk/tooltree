Tooltree Build
#####


Tooltree Changes
====

I've made some drastic changes to the project recently (Sep-2024).  The
goals were:

 - Enable external projects to leverage Tooltree packages.

 - Simplify the build system -- reduce the number of "moving parts".

 - Use Minion instead of Crank for builds.

 - Remove unused packages.

More specifically:

 - The following packages have been dropped: p4x, pakman, simp4, cdep,
   ctools, crank.

 - Two-phase, two-level builds have been abandoned.

   Formerly, a "make configure" step at the top level of the project built a
   project configuration file that described the entirety of the build,
   determining what a subsequent "make all" would do, both at the project
   and package level.  Instead of this, all potential targets are always
   available, and the default targets at project and package level are
   hardcoded.

   `SUBDIR/Package` files are no longer supported.  This information, along
   with the configuration data formerly in the top-level Makefile (where
   packages are located, what variants are built) is now in
   `build/tooltree.mk`, so it can be leveraged by external makefiles.

   Package-level makefiles can build the entire project, and the top-level
   makefile is just a package that builds a selected set of packages.

 - Many build features have been dropped.

   This includes support for Windows/Cygwin builds, support for multiple
   toolchains, cross-target builds, and valgrind builds.

   These features introduced a fair amopunt of complexity in the build
   system and is no longer actively used.  In cross-target builds, for
   example, the MDB package's "release" variant could make use of both the
   "host" (build machine) variant and the "release" (target) variant of the
   Lua package.  This is not *currently* supported in the Minion-based
   builds.

   The original Crank sources, in all their glory, are still there in the
   history, and on the "crank" branch.

 - [Minion](https://github.com/bhk/minion) replaces Crank.

   Minion retains the "functional OO" flavor of Crank, but is more refined.
   It addresses the most common pain points of Crank.

   Minion supports more readable syntax for property definitions -- `{prop}`
   vs. `$(call .,prop)`-- and more powerful ways of defining instances
   ("items" in Crank) -- as in `Copy(Exe(foo.c),dir:exports)`.

   Minion understands dependencies between instances, because inputs and
   dependencies can be specified as instance names, not just file names.
   These instance names are automatically translated to output file names
   for use in command-line contexts (e.g. {^} and {@}).  In Crank,
   intermediate files would often have have to be explicitly named, and it
   leaned on classes not just as types, but as collections of files.

   Minion makefile goals are explicit and easy to trace.  In Crank, aliases
   were defined as side effects via the `prereqOf` property.  Class names
   were available as phony targets, and were implicitly a preqreq of "all"
   (the default goal).

   Minion makefiles are purely functional, relying on subclassing to
   customize build behavior.  They do not override Minion's variable
   definitions; minion.mk is included only at the *end* of the user
   makefile.  Crank makefiles would often need to override or modify
   property definitions, which introduced brittle dependencies on class
   implementations.

   Cached (pre-compiled) rules are on by default in Crank, so makefiles have
   to use `<wildcard>` and `<shell>` to avoid consistency problems.  In
   Minion, caching must be explicitly enabled, and small makefiles are
   plenty fast without it.

   This Crank example:

   .  CC += $(call <wildcard>,*.c)        # include rules to compile these
   .  Exe += prog
   .  Exe[prog].prereqOf = prog           # `prog` goal defined here (& elsewhere?)
   .  Exe[prog].in = $(call get,out,CC)   # accepts files, not items

   In Minion is:

   .  Alias(prog).in = Exe(@prog)
   .  prog = $(wildcard *.c)

 - External projects are supported.

   Projects can now live outside the tooltree directory structure and
   leverage tooltree without making any modifications to tooltree files.
   A single-package project makefile could be this simple:

   .  Alias(default).in = LuaExe(prog.lua) LuaTest@*_q.lua
   .  include-imports = build-lua/build-lua.mk
   .  include <PATH-TO-TOOLTREE>/build/tooltree.mk

   A project with multiple packages would define its own project-level
   include file that includes and extends `tooltree.mk`:

   .  # project.mk
   .
   .  # this will be included from Makefiles in other directories...
   .  projdir := $(dir $(lastword $(MAKEFILE_LIST)))
   .
   .  package.foo.dir := $(projdir)foo
   .  package.foo.outdir = .
   .  package.bar.dir := $(projdir)bar/
   .  package.bar.outdir = $(VOUTDIR)/exports
   .
   .  include $(projdir)/<PATH_TO_TOOLTREE>/tooltree.mk

   Its package makefiles would resemble those in tooltree:

   .  # foo package Makefile
   .  Alias(default).in = Ship(exports) LuaTest@*_q.lua
   .  exports = LuaExe(foo)
   .
   .  include-imports = build-lua/build-lua.mk
   .  include ../project.mk
