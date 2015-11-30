-- p4x

local helpText = {
usage = [=[
    Usage: P4X <command> [directories/options]

    Commands:

      status      List workspace files that differ from depot.
      addremove   Make local changes known to the server.
      find        Search for files on the local disk.
      scrub       Eliminate local deviations from the depot.
      ls          List files in the repository
      xintegrate  Integrate between p4 servers.
      help        Describe P4X or its sub-commands.

    For more information use "P4X help <topic>", where <topic> is a
    command name or one of:  options, config, views, history
]=],

status = [=[
    status:  List workspace files that differ from depot.

      P4X status [options] [<dirs>]

    Status describes how a local directory tree differs from the current
    revision of the Perforce depot tree.  It lists all divergent files,
    prepending them with one of the following characters to indicate their
    status:

        ? - Present locally but not tracked in Perforce
        ! - Tracked, but missing a local copy
        M - Tracked, unopened, but not readonly
        E - Tracked, opened for edit
        D - Tracked, opened for delete (remove)
        A - Opened for add
        a - Opened for add, but missing a local copy

    "Tracked" refers to the Perforce notion of "have revision" -- what the
    server expects to be in the client -- so the status command indicates
    changes made to the local workspace since the last "p4 sync".

    Zero or more directories may be listed on the command line.  If none are
    given, "."  is used.

    Status ignores files that are not included in "statusView" if that
    setting is present in the config file (see "P4X help config" for more
    info).  Use "--all" to examine all files even when statusView is set.

    See "P4X help options" for info on options.
]=],

xintegrate = [=[
   xintegrate:  Integrate files from a different server.
      P4X xintegrate [options] <from> <to>

   Xintegrate integrates changes made on one server to another.

   First xintegrate will find a common baseline for the changes.  It
   will do this by comparing <from> and <to> versions in this order:
      <from>#head          <to>#head
      <from>#head          <to>#head - 1
      <from>#head          <to>#head - 2
      ...
      <from>#head          <to>#1

      <from>#head - 1      <to>#head
      <from>#head - 1      <to>#head - 1
      <from>#head - 1      <to>#head - 2
      ...
      <from>#head - 1      <to>#1
      ...
      <from>#1             <to>#1

   Xintegrate will then perform a 3 way merge between <to>#baseline,
   <from>#head and <to>#head.  If there are no conflicts xintegrate
   will 'p4 edit <to>` and write the merged output in its place.

   If a conflict exists and the user specified --resolve option,
   xintegrate will run the resolvetool (p4merge by default) so the
   user can interactively resolve the conflicts.  The interactive
   loop requires that the resolve program terminate for merge to
   proceed.

   New files are only added if one of the actions from the <from>
   files was an add and the destination file was not present.
   Otherwise if a destination file is not present and there is no
   'add' action in the <from> changes, the file is ignored.  This
   means that you cannot use xintegrate to incrementally add
   changelists from one tree to another.  You must submit the
   destination tree between calls to xintegrate.


   Xintegrate will leave new and modified files in either "add" or
   "edit" state, and it will skip merging files that are in that
   state when xintegrate is run.

   For example:
      p4x xintegrate ../qctp406/pkg/foo/... ../aswp401/some/vce/path/foo/...
      cd ../aswp401/some/vce/path/foo
      p4 commit -d "integrate foo from qctp406 server" ...

   It is recommended that the user use P4CONFIG environment variable
   and set P4PORT and P4CLIENT in those p4config files in the <to>
   and <from> directories.  Xintegrate will use -d option when
   executing p4 to switch to the appropriate directory when issuing
   commands.

   Options: 
      --fromp4=<p4 command>
         P4 command to use for <from> files.
      --top4=<p4 command>
         P4 command to use for <to> files.
      --diff=<diff command>
         Set the diff command for comparing baselines.  Default
         is set to 'diff -dba #{from} #{to}'.
      --diff3=<diff3 command>
         Test automerge. Default is set to:
            'diff3 -x  #{to} #{baseline} #{from}' 
      --merge=<merge command>
         Automerge command. Default is set to:
            'diff3 -m #{to} #{baseline} #{from} > #{output}'
      --resolve
	      Resolve failed merges interactively with the resolvetool.
	      Tool must save to the output file and exit.
      --resolvetool=<interactive merge tool>
         Interactive merge tool for resolving conflicts.
            'p4merge #{baseline} #{from} #{to} #{output}'
]=],


scrub = [=[
    scrub:  Eliminate local deviations from the depot.

      P4X scrub [options] [<dirs>]

    Scrub deletes local changes to make a local workspace consistent
    with the repository.  The following table summarizes actions to be
    taken for each status code (see "P4X help status" for more info on
    status codes):
      
        ?  =>  rm
        !  =>  p4 sync -f
        M  =>  p4 sync -f
        a  =>  p4 revert

    Scrub lists all actions to be performed, but it does not modify the
    local workspace UNLESS the "--force" option is specified.

    Scrub limits results to "scrubView" if present in the config file.  Use
    "--all" to examine all files.  See "P4X help config" for more info.

    "P4X scrub --force" followed by "p4 sync" should yield similar
    results to "rm -rf" followed by "p4 sync -f", only much faster.

    See "P4X help options" for info on options.
]=],

addremove = [=[
    addremove:  Make local changes known to the server.

      P4X addremove [options] [<dirs>]

    Addremove makes local changes known to the depot by performing
    the following commands on local files depending on their status:

        ?  =>  p4 add
        !  =>  p4 delete
        M  =>  p4 edit
        a  =>  p4 revert

    Addremove lists all actions to be performed, but it does not actually
    update the Perforce server unless the "--force" option is specified
    or "addremoveNoConfirm" is set to 'true' in the configuration file.

    When addremove issues a "p4 edit" command or finds existing files in
    the "edit" state, p4x will issue a "p4 revert -a" command to revert
    files whose contents have not changed.

    Use "--new" to treat all read-only files as if they were writable,
    causing all files to be compared based on contents.

    Addremove ignores files that are not included in "statusView" if that
    setting is present in the config file (see "P4X help config" for more
    info).  Use "--all" to examine all files even when statusView is set.

    Try "P4X help options" for info on options.
]=],

find = [=[
    find:  Search for files on the local file system.

      P4X find <pattern>...

    Find works like 'p4 files', but it searches the local file system
    instead of the repository.

    P4X pattern syntax is an extension of Perforce patterns:

       ?         matches any one character other than "/"
       *         matches zero or more characters other than "/"
       ...       matches zero or more characters, including "/"
       [abc]     matches one character from "abc"
       (a|b|c)   matches either "a" or "b" or "c"

    Patterns may take the form of relative paths, in which case they are
    considered relative to the current working directory.

    If multiple patterns are supplied they will be combined like clauses
    in a view.  For example, if a pattern begins with a "-", it will
    exclude files matched files from the set matched by previous patterns.
    Note that "--" must be used to terminate option processing before a
    clause that begins with "-" can appear on the command line.  Also, if
    a pattern contains a newline character (which is possible in UNIXes)
    the lines will be treated as separate clauses in a view.  See "P4X
    help views" for more on views.

    The --print0 option (or its alias -0) can be used to deal with file
    names that contain spaces.

    Examples:

        "P4X find -- x/... -....o" will list files under directory 'x'
        that do not end in ".o"

        "P4X find ....c -0 | xargs -0 wc" will count lines in all the ".c"
        files in the current directory and descendant directories, properly
        handling files with spaces in their names.

]=],

ls = [=[
    ls:  List files in the repository

      P4X ls <pattern>...

    The output of "P4X ls" mimics "ls -l", displaying flags, file size, the
    date of the most recent revision, and the file name.  For example:

          -rw------- 4754    Sep 10 2009 lbitlib.c

    The first four flags are analogous to those in "ls -l":

            d/l    d = directory, l = symlink
              r    file is mapped into local client
              w    file is currently opened for some action
              x    file is an executable file

    The last five flags carry Perforce-specific information about the file
    type.  See "p4 help filetypes" for more info.

               c   stored compressed on server
               k   keyword expansion in effect
               m   always set modtime
               W   always writable on client
         b/a/u/U   binary / apple / unicode / utf16

    The patterns passed on the command line to P4X ls should refer to
    directories.  Either local paths or depot paths may be used.
]=],

options = [=[
    P4X options:

    Options are order-independent and may be specified before or after
    other arguments.  Options arguments can be given as the next word on
    the command line OR as a suffix ( "=<value>").

    --force : Cause "addremove" and "scrub" commands to perform actions
        that may modify the local workspace or current changelist.  No
        user confirmation will be requested.

    --all : Examine all files whether or not a view would normally be in
        effect.  See "P4X help views".

    --new : Treat non-writable local files as writable.  This causes
        addremove to check for changes based on file contents.

    --config=<name> : Use <name> when looking for a config file,
        overriding the default.  An empty file name ("--config=") causes
        P4X to use no config file.  See "P4X help config".

    --p4=<p4command> : Use <p4command> to invoke the Perforce client.
        The default is "p4".  This overrides the "p4Command" setting in
        the config file.

    --log=[+]<file> : Log details of operations performed to <file>.  If "+"
        is present before the file name, file contents are preserved and
        logged data will be appended.

    --print0, -0 : Terminate each file name with a null byte instead of a
        newline character (for "find" and "status").

    "--" by itself terminates options processing, ensuring subsequent
    arguments will not be confused with options.
]=],

config = [=[
    P4X config files

      By default, P4X looks for a config file named ".p4x" in the current
      directory (or if not there, in any of its parent directories).  You
      can use the "--config" option to set this to some other file name, or
      to disable this feature.

      Config files are Lua files that may assign one or more of the following
      variables:

         statusView: view to use for status & addremove
         scrubView:  view to use for scrub
         p4Command:  command to use when invoking the perforce client
         default:    the default subcommand
         log:        filename to log output to (see "--log")
         addremoveNoConfirm : if true, "--force" is the default for addremove

      Example config file:

          -- for status & addremove include files that are
          -- typically subject to version control
          statusView = [[
             ...
             -.../.*
             -...(o|obj)
          ]]
          -- for scrub include just about everything
          scrubView = [[
             ...
             .../.p4x
          ]]
          p4Command = "p4"     -- this is the default
          default = "status"   -- most frequent
          log = "+/tmp/p4xlog" -- append log data here

    Use "P4X help views" for more information on views.
]=],

views = [=[
    views

      By default, P4X commands that operate on local directories (status,
      addremove, scrub) look for a view specification that will restrict the
      set of files they examine.  If the view is not found, all files under
      the specified directory will be examined.  Status and addremove use
      the "statusView" view, and scrub uses the "scrubView" view.

      Each line of a view may include clauses that include or exclude files
      from consideration. They are processed in order, as in a Perforce
      client specification, and use pattern syntax similar to Perforce
      client specifications, but with extensions.  Each clause takes one of
      the following forms:

        <pattern>   : include files matching <pattern>
        -<pattern>  : exclude files matching <pattern>
        &<pattern>  : restrict set to files also matching <pattern>

      See "P4X help find" for more on patterns.

      Patterns that are relative paths will be considered relative to the
      directory containing the config file that contains the view.

      Empty lines (all whitespace) are ignored.  A '#' anywhere on a line
      begins a comment.

      Example:

        ...                            # include <curdir>/...
        -.../*_(Debug|Release)/...     # exclude files in these dirs
        &....(c|h|lua|py)              # include only source files
]=],

version = [=[
p4x <VER>
]=],

history = [=[
New in 0.998:

 * Quote arguments for shell (e.g. file names with spaces).

New in 0.997:

 * Fixed bug introduced in 0.996

New in 0.996:

 * Fixed bug that prevented 'ls' from working on Windows.

New in 0.995:

 * 'ls' subcommand

New in 0.994:

 * "addremoveNoConfirm" config file option.

New in 0.993:

 * Fixed: addremove was not issuing 'p4 edit' for "M" files (files locally
   modified but not in the 'edit' state)

 * "--new" option to treat all local files as writable.

 * Addremove issues "p4 revert -a <dir>" for all dirs.

New in 0.992:

 * Ignore case of drive letter on Windows when applying views;
   rare condition caused p4x to ignore all local files.

New in 0.991:

 * --print0 (or -0) option for zero-terminating 'find' and 'status'
   output lines.

New in 0.98:

 * Fixed handling of files opened for 'add' but missing locally; affects
   status, scrub, and addremove.

New in 0.97:

 * Fixed scrub problem: scrub --force would try (and fail) to remove
   directories when they contain no files but contain other directories
   that do contain files.

 * Scrub without "--force" now shows 'rmdir' commands that will be executed.

New in 0.96:

 * Fixed progname and logging problem.

 * Added "--log=" option and log=<...> config file option.

New in 0.95:

 * Fixed "--config=..." not being recognized.

 * Default command = "help".

New in 0.94:

 * addremove robustly handles case conflicts and directory/file
   conflicts when propagating local changes to the server.
   This requires renaming files/directories prior to issuing
   'p4 delete' commands, and the restoring the original names.

 * scrub removes empty directories, and succeeds when a directory
   has been replaced by a file.

 * Config files introduced.  .p4xstatus and .p4xscrub removed.
   See "p4 help config".

New in 0.93:

 * File name comparison is case-sensitive even on Windows to
   detect when the local case deviates from the depot.

Pending issues:

 * Error opening a directory should cause it to skip the directory, not fail
   the entire enumeration.  (But log the error...)

 * Properly quote file names in Win32 and UNIXes when invoking p4, or
   use '-x-'.

 * Option to output LF (not CRLF) for WinNT builds.

 * Ignore writable files that P4 checks out as writable.

]=]
}

local lfsu = require "lfsu"
local xpfs = require "xpfs"
local tree = require "tree"
local Object = require "object"
local errors = require "errors"
local getopts = require "getopts"
local config = require "config"
local version = require "version"
local fu = require "lfsu"
local fsu = require "fsu"
local xpexec = require "xpexec"

local progname = (arg[0] or "pakman"):match("([^/\\]*)$")
if progname:match("%.") then
   progname = progname:match("(.*)%.")
end

helpText.version = helpText.version:gsub("<VER>", version.versionStr)

local isWindows = fu.iswindows

-- cfgData is the global environment of the config file.
--
local cfgData = {}
setmetatable(cfgData, { __index = function(t,k) return rawget(_G,k) end } ) -- inherit globals

local opts
local p4Command

local logFile = nil
local function logf(...)
   if logFile then
      logFile:write(string.format(...))
   end
end

local function addLogFile(file)
   if not file then return end
   if type(file) == "string" then
      local mode = "w"
      if file:sub(1,1) == "+" then
         file = file:sub(2)
         mode = "a+"
      end
      file = assert( io.open(file, mode) )
   end
   local old = logFile
   logFile = file
   if old then
      logFile = { write = function (_,...) old:write(...) ; return file:write(...) end,
                  close = function ()  old:close() ; return file:close() end }
   end
end

local function printf(...)
   local s = string.format(...)
   io.write(s)
   if logFile then logFile:write(s) end
end

local function fatal(...)
   error("exit: " .. string.format(...))
end

local time0
local function time()
   local t = os.time()
   time0 = time0 or t
   return t - time0
end

-- 'cmd' is passed literally to the shell; if it contains unquoted spaces
-- they will delimit options.  All other strings in the argument list
-- will be quoted before being passed to the shell.
--
local function procRead(cmd, ...)
   local command = cmd .. " " .. xpexec.quoteCommand(...)
   local f = io.popen(command .. " 2>&1")
   logf("%% %s >%s\n", command, (f and "" or "[error]"))
   return f, command
end


--------------------------------
-- File utilities
--------------------------------

local function ident(a) return a end

local eqform, prettify = ident, ident

if fu.iswindows then
   function eqform(path)
      return path:lower():gsub("\\", "/")
   end
   function prettify(path)
      return path:gsub("\\", "/"):gsub("^[A-Z]:/", string.lower)
   end
end

local curdir = xpfs.getcwd()
local curbase = eqform(curdir):gsub("[^/]$", "%1/")

local function relpath(path, dotslash)
   local pre = path:sub(1,#curbase)
   if pre == curbase or eqform(pre) == curbase then
      local rel = path:sub(#curbase+1)
      return (dotslash and "./"..rel or rel)
   end
   return path
end

local function exist(fname)
   return xpfs.stat(fname) ~= nil
end

-- Find 'real' name of file (the name we get when enumerating a directory).
-- NOTE: This function fixes only the final path element.
--
local function realname(file)
   local dir, leaf = fu.splitpath(file)
   for _, f in ipairs(xpfs.dir(dir)) do
      if f:lower(f) == leaf:lower() then
         return fu.resolve(dir, f)
      end
   end
   io.stderr:write("error: Could not file real name of: " .. file .. "\n")
end

local function rename(from,to)
   printf("mv %s %s\n", relpath(from,true), relpath(to,true))
   os.rename(from, to)
   return true
end

-- Return array of parsed p4 fstat results as records:
--    { clientFile=..., depotFile=..., action=..., ...}
--
-- Client-mapped files ("-Rc") are returned.  Notable fields:
--    clienFile=<localPath>
--    haveRev=nil          => file not synced
--    headAction="delete"  => file is deleted (but client might still 'have')
--
-- On entry:
--   'pattern' = p4 file matching pattern
--
local function p4fstat(pattern, opts, bAll, p4C)
   local results = {}
   local entry = {}
   local p4Command = p4C or p4Command
   local function finishEntry()
      if bAll and next(entry) or entry.clientFile then
    table.insert(results, entry)
      end
      entry = {}
   end
   local f = procRead(p4Command, "-s", "fstat", opts or "-Rc", pattern)
   if not f then
      error("p4: could not execute p4")
   end
   local errline = ""
   for line in f:lines() do
      logf(" | %s\n", line)
      local name,value = line:match("^info%d: ([^ ]*) (.*)")
      if name == "depotFile" then
         finishEntry()
      end
      if name then
         entry[name] = value
      elseif line:match("^exit:") then
         -- exit code?
      elseif line ~= "" then
         errline = line
         break
      end
   end
   finishEntry()
   f:close()

   local nosuch = errline:match(" %- no such file") or errline:match(" %- no file%(s%)")

   if errline:match(" %- file%(s%) not in client view") or
      errline:match("Path .* is not under client's root") then
      error("p4: file(s) not in client view")
   end
   if errline ~= "" and not nosuch then
      error("p4: mal-formed p4 fstat response: " .. errline)
   end
   if not results[1] and not nosuch then
      error("p4: p4 fstat failed")
   end

   return results
end


local function p4dirs(pattern)
   local dirs = {}

   local f = procRead(p4Command, "-s", "dirs", pattern)
   for line in f:lines() do
      logf(" | %s\n", line)
      local status,name = line:match("^(%w+): (.*)")
      if status == "info" then
         table.insert(dirs, name)
      end
   end
   f:close()
   return dirs
end


local function nixCmpForm(path)
   return path
end

-- On Windows, compare file names in case-sensitive manner to detect
-- when local workspace has wrong case.  (But ignore case of drive
-- letter.  P4 may return either case for the drive letter depending on
-- how the client root is specified.)
--
local function winCmpForm(path)
   if path:match("^[A-Z]%:") then
      path = path:gsub("^[A-Z]", string.lower)
   end
   return path:gsub("\\", "/")
end

local cmpForm = isWindows and winCmpForm or nixCmpForm

-- Return array of records, one per file:
--    f.name = file name (absolute local path)
--    f.st   = status code, as documented above but also including:
--                "." => file in synch with depot
--
-- Status codes overlap with those in use by Subversion and Mercurial, and
-- perhaps other VCS's.  !, ?, M, and A are common to svn and hg.
--
local function compareFiles(dir, viewName)

   -- Enumerate local files

   if dir:sub(-1,-1) == "/" then
      dir = dir:sub(1,-2)
   end

   logf("# Find files under '%s' [time=%d]\n", dir, time())

   local spec
   local src = viewName and cfgData[viewName]
   if src then
      local cfgdir = fu.splitpath(cfgData.file)
      spec = tree.parseSpec(src, cfgdir)
      logf("# Using '%s' from %s\n", viewName, cfgData.file)
   else
      local function trueF() return true end
      spec = { ftest = trueF, dtest = trueF }
   end

   local a, dirs = tree.findx({dir}, spec)

   if logFile then
      logFile:write(string.format("%d files found:\n", #a))
      for _,f in ipairs(a) do
         logFile:write("   " .. f.name .. "\n")
      end
   end

   -- Enumerate files known to server

   local statarg = dir .. "/..."
   logf("# start fstat %s [time=%d]\n", statarg, time())
   local b = p4fstat(statarg)
   logf("# end fstat [time=%d]\n", time())

   -- Construct key (normalized file name) and index (keyed on 'key' field)
   local ndx = {}
   for _,f in ipairs(a) do
      local key = cmpForm(f.name)
      assert(ndx[key] == nil)
      f.key = key
      ndx[key] = f
      f.st = "?"
   end

   local actions = { edit = "E", add = "A", delete = "D" }

   -- Visit files known to p4 and assign status codes
   for _,fb in ipairs(b) do
      -- ignore files missing from the 'have' revision (e.g. deleted)
      -- but include pending files
      if fb.haveRev or fb.action then
         local key = cmpForm(fb.clientFile)
         local fa = ndx[key]
         if fa then
            fa.st = actions[fb.action] or
                    (opts.new or fa.perm:sub(3,3)=="w") and "M" or "."
         elseif spec.ftest(key) then
            -- not present locally
            local st = (fb.action == "delete") and "D" or
                       (fb.action == "add") and "a" or "!"
            table.insert(a, {key=key, st=st, name=prettify(fb.clientFile)})
         end
      end
   end

   local function sortCmp(x,y)
      return x.st > y.st or x.st == y.st and x.key < y.key
   end
   table.sort(a, sortCmp)

   return a, dirs
end


----------------------------------------------------------------
-- Action object: perform actions on files based on status
----------------------------------------------------------------

local Actions = Object:new()

function Actions:initialize(stActions)
   -- buckets associated with various types of actions
   self.add = {}
   self.delete = {}
   self.revert = {}
   self.edit = {}
   self.rm = {}
   self.sync = {}
   self.trackEdit = {}

   self.stLists = {}    -- e.g. '?' -> self.add

   for k,v in pairs(stActions) do
      self.stLists[k] = self[v]
   end
end

-- This method is called once for every record output by compareFiles
--
function Actions:visitFile(fcmp)
   local lst = self.stLists[fcmp.st]
   if lst then
      table.insert(lst, fcmp.name)
   end
end

function Actions:visitDirs(dirs, fcmps)
   -- Keep track of which directories are used by depot files
   local du = self.dirsUsed
   if du then
      for _,d in ipairs(dirs) do
         du[cmpForm(d)] = false
      end
      for _,f in ipairs(fcmps) do
         if f.st ~= "?" then
            local dir, dirOld = f.key
            -- mark dir and all parent dirs used
            while true do
               dirOld, dir = dir, (fu.splitpath(dir))
               if du[dir] then break end
               du[dir] = true
            end
         end
      end
   end
end

-- Enumerate local and depot files and compare, then take actions
-- on each resulting record.
--
--   words = arguments to sub-command
--   viewName = default view name
--
function Actions:compareFiles(dirs, viewName)
   if not dirs[1] then
      dirs = {"."}
   end
   self.dirs = dirs

   if opts.all then viewName = false end

   -- put files into appropriate buckets
   for _,dir in ipairs(dirs) do
      local fcmps, dirs = compareFiles(dir, viewName)
      self:visitDirs(dirs, fcmps)
      for _,fc in ipairs(fcmps) do
         self:visitFile(fc)
      end
   end

   if self.dirsUsed then
      -- sort unused directories
      local rmdirs = {}
      for d,u in pairs(self.dirsUsed) do
         if not u then
            table.insert(rmdirs, d)
         end
      end

      table.sort(rmdirs, function (a,b) return a > b end)
      self.rmdirs = rmdirs
   end

   if opts.force then
      self:exec()
   else
      self:show()
   end
end

function Actions:show()
   local count = 0
   local p4cmd = self.p4Command or p4Command
   local cmds = {
      rm     = "rm",
      sync   = "p4 sync -f",
      delete = "p4 delete",
      edit   = "p4 edit",
      add    = "p4 add"
   }

   for _,action in ipairs{ "rm", "sync", "delete", "edit", "add" } do
      for _,f in ipairs(self[action] or {}) do
         local cmd = cmds[action]:gsub("^p4", p4cmd)
         printf("%s %s\n", cmd, f)
         count = count + 1
      end
   end

   -- remove unused directories
   if self.rmdirs then
      for _,d in ipairs(self.rmdirs) do
         printf("rmdir %s\n", d)
         count = count + 1
      end
   end

   printf("# %d actions to be performed.\n", count)
   if count > 0 then
      printf("# Use '--force' to perform these without further confirmation.\n")
   end
end


-- Rename f to a name that does not conflict with any existing files or
-- pending renames.
--
local function moveAside(f, avoid)
   -- find its real name so we can rename it back
   local freal = realname(f)
   if not freal then
      printf("warning: realname(%s) failed\n", f)
      return nil
   end

   for _,suffix in ipairs{ "_a", math.random(9999999), math.random(9999999) } do
      local b = freal..tostring(suffix)
      if not exist(b) and not avoid[b:lower()] then
         if rename(freal, b) then
            return b, freal
         end
      end
   end
end

-- Undo renames
--
local function unmove(bkups)
   for f,b in pairs(bkups) do
      rename(b, f)
   end
end

local function exec(...)
   -- execute command
   local f, cmd = procRead(...)

   -- report command issued
   printf("%s\n", cmd)

   if f then
      for line in f:lines() do
         logf(" | %s\n", line)
      end
   end
   f:close()
end

-- Perform p4 command on set of files
--
local function p4_x_(p4args, files)
   for _,f in ipairs(files) do
      exec(p4Command, p4args, relpath(f,true))
   end
end

function Actions:exec()
   -- perform rm operations
   for _,fname in ipairs(self.rm) do
      printf("rm %s\n", fname)
      xpfs.remove(fname)
   end

   -- remove unused directories
   if self.rmdirs then
      for _,d in ipairs(self.rmdirs) do
         printf("rmdir %s\n", d)
         xpfs.rmdir(d)
      end
   end

   -- perform sync -f operations
   p4_x_({"sync","-f"}, self.sync)

   local bkups = {}
   local avoid = {}

   -- protect clobber
   --
   -- On case collision, avoid clobbering *other* files.  For example, when
   -- deleting "TEST", we don't want to clobber "test".  It is difficult to
   -- predict whether two names collide, because we don't know which type of
   -- FS (and if we knew that we still wouldn't know ALL the details).  So
   -- we test for the existence of each file before performing 'delete'.
   --
   for _,f in ipairs(self.delete) do
      avoid[f:lower()] = true
   end
   for _,f in ipairs(self.delete) do
      if exist(f) then
         local b,orig = moveAside(f, avoid)
         if not b then
            printf("Could not rename: %s; aborting addremove.\n", f)
            unmove(bkups)
            return
         end
         bkups[orig] = b
         --printf("backup %s %s\n", relpath(f), relpath(b))
      end
   end

   -- perform deletes
   p4_x_("delete", self.delete)

   -- perform reverts
   p4_x_("revert", self.revert)

   -- unclobber
   unmove(bkups)

   -- perform adds, edits
   p4_x_("edit", self.edit)
   p4_x_("add", self.add)
end

----------------------------------------------------------------
----------------------------------------------------------------

local commands = {}

----------------------------------------------------------------
-- p4 path object
----------------------------------------------------------------
local p4path = {}
function p4path:versioned()
   if self.rev then
      return table.concat({self.path, "#", self.rev})
   elseif self.change then
      return table.concat({self.path, "@", self.max})
   elseif self.max and self.min then
      return table.concat({self.path, "@", self.min, ",", self.max})
   else
      return self.path
   end
end
function p4path:iswild()
   return self.path:match('^%.%.%.$')
end
function p4path.new(path, cfg)
   local mt = { __index = p4path }
   cfg = cfg or {}
   local obj = { path = path:match("(%S+)#%d+") or path:match("(%S+)@%d+") or path
               , min = cfg.min or path:match("%S+@(%d+),%d+")
               , max = cfg.max or path:match("%S+@%d+,(%d+)")
               , change = cfg.change or nil == path:match("%S+@%d+,%d+") and path:match("%S+@(%d+)")
               , rev =  cfg.rev or path:match("%S+#(%d+)")
               }
   setmetatable(obj, mt)
   assert(obj:versioned())
   return obj
end


----------------------------------------------------------------
-- p4
----------------------------------------------------------------
local p4 = {}
function p4.new(cfg)
   local mt = { __index = p4 }
   local obj = { p4 = cfg.p4
               , port = cfg.port
               , dir = cfg.dir
               , client = cfg.client
               }
   setmetatable(obj, mt)
   return obj
end

function p4:command()
   local cmd = {self.p4
               ,self.client and "-c " .. self.client or ""
               ,self.port and "-p " .. self.port or ""
               ,self.dir and "-d " .. self.dir or ""
               }
   return table.concat(cmd, " ")
end

function p4:add(to)
   return assert(p4.exec(self:command(), "add", to):match("opened for add"), "p4:add")
end

function p4:delete(to)
   return assert(p4.exec(self:command(), "delete", to):match("opened for delete"), "p4:delete")
end

function p4:edit(to)
   return assert(p4.exec(self:command(), "edit", to):match("opened for edit"), "p4:edit")
end

function p4:print_to(from, to) 
   return assert(p4.exec(self:command(), "print", "-q", "-o", to, from:versioned()), "p4:print_to")
end

function p4.exec(...)
   local f = procRead(...)
   if f then
      local rv = f:read("*a")
      f:close()
      return rv
   end
end

function p4.exec_fmt(fmt, vars)
   for i,v in pairs(vars) do 
      fmt = fmt:gsub("#{"..i..".-}",v)
   end
   return p4.exec(fmt)
end

function p4.xdiff(args, from, to)
   local fromf = os.tmpname()
   local tof = os.tmpname()
   from.p4:print_to(from.path, fromf)
   to.p4:print_to(to.path, tof)
   local rv = assert(p4.exec_fmt(args.diff, { from = fromf, to = tof}), "p4.xdiff")
   os.remove(fromf)
   os.remove(tof)
   return rv
end

function p4.xmerge(args, baseline, from, to)
   local basef = os.tmpname()
   local tof = os.tmpname()
   local fromf = os.tmpname()
   from.p4:print_to(from.path, fromf)
   to.p4:print_to(baseline, basef)
   to.p4:print_to(to.path, tof)
   local outf = to.p4:where(to.path).clientFile
   local diff3 = assert(p4.exec_fmt(args.diff3,{baseline=basef,from=fromf,to=tof}), "p4.xmerge")
   if diff3:len() > 0 then
      if args.resolve then
         to.p4:edit(to.path.path)
         local done = false
         while done == false do
            print(string.format("interactive 3 way merge of baseline=%s from=%s to=%s", baseline:versioned(), from.path:versioned(), to.path:versioned()))
            print(string.format("current resolve tool command '%s'", args.resolvetool))
            print("(a)ccept current (r)un resolve tool (c)hange resolve tool: ")
            cmd = io.read("*l")
            local cmds = {}
            function cmds.a() 
               done = true 
            end
            function cmds.r()
               p4.exec_fmt(args.resolvetool,{baseline=basef,from=fromf,to=tof,output=outf})
            end
            function cmds.c()
               print("enter new resolve tool command: ")
               args.resolvetool = io.read("*l")
            end
            if cmds[cmd] then
               cmds[cmd]()
            end
         end
      else
         error(string.format("\n\tRerun with --resolve. 3 way merge failed:\n\t\tbaseline=%s\n\t\tfrom=%s\n\t\tto=%s", baseline:versioned(),from.path:versioned(), to.path:versioned()))
      end
   else
         to.p4:edit(to.path.path)
         p4.exec_fmt(args.merge,{baseline=basef,from=fromf,to=tof,output=outf})
   end
   os.remove(basef)
   os.remove(fromf)
   os.remove(tof)
end

-- return an array of p4paths from the filelog history with the "action" field
function p4:where(path)
   local data = assert(p4.exec(self:command(), "where", type(path) == 'string' and path or path.path), "p4 where")
   local rv = {}
   rv.depotFile,rv.viewFile,rv.clientFile = data:match("(%S+)%s+(%S+)%s+(%S+)")
   return rv
end

function p4:fstat(path)
   return p4fstat(path:versioned(), nil, true, self:command())
end

function p4:filelog(path)
   local results = {}
   local entry = {}
   local f = assert(procRead(self:command(), 'filelog', '-i', path:versioned()), "p4 filelog")
   local file = nil
   for line in f:lines() do
      if line:match("^(//%S+)") then
         file = line:match("^(//%S+)")
      elseif line:match("^... #(%d+) change (%d+)") then
         assert(file)
         local rev,change,action = line:match("^... #(%d+) change (%d+) (%S+)")
         local ff = p4path.new(file,{ rev = rev, change = change })
         ff.headAction = action
         table.insert(results, ff)
      end
   end
   f:close()
   return results
end


----------------------------------------------------------------
-- xintegrate
----------------------------------------------------------------
function commands.xintegrate(words, args)
   local from = words[1]
   local dir,from = fu.splitpath(from)
   from = p4path.new(from)
   local fp4 =  p4.new({dir = lfsu.abspath(dir), p4 = args.fromp4 or "p4" })

   local to = words[2]
   local dir,to = fu.splitpath(to)
   to = p4path.new(to)
   local tp4 =  p4.new({dir = lfsu.abspath(dir), p4 = args.top4 or "p4"})
   args.diff = args.diff or "diff -dba #{from} #{to}"
   args.diff3 = args.diff3 or "diff3 -x #{to} #{baseline} #{from}"
   args.merge = args.merge or "diff3 -m #{to} #{baseline} #{from} > #{output}"
   args.resolvetool = args.resolvetool or "p4merge #{baseline} #{to} #{from} #{output}"

   local fromfiles = fp4:fstat(from) 
   local tofiles = tp4:fstat(to) 
   local tobypath = {}
   for _,tt in ipairs(tofiles) do
      tobypath[fsu.nix.relpathto(tp4.dir, tt.clientFile)] = tt 
   end
   for _,ff in ipairs(fromfiles) do
      local fromstem = fsu.nix.relpathto(fp4.dir, ff.clientFile)
      local tt
      if to:iswild() then
         tt = tobypath[fromstem]
      else
         assert(not from:iswild(), "wild card pattern present in <from> path but not <to> path")
         --file may not exist yet
         tt = tofiles[fromstem]
      end
      if tt then
         if tt.action == "edit" or tt.action == "add" then
            goto nextfile
         end
      end
      local fversions = fp4:filelog(p4path.new(ff.depotFile, from))
      for fi,fv in ipairs(fversions) do
         if tt == nil then
            if fv.headAction == "add" then
               --found baseline, print the latest there
               local tostem = to:iswild() and fromstem or to:versioned()
               local todest = tp4:where('.').clientFile .. '/' .. tostem
               fp4:print_to(fversions[1], todest)
               tp4:add(todest)
            end
            goto nextfile
         elseif fv.headAction == "delete" and tt ~= nil then
            tp4:delete(tt.depotFile)
            goto nextfile
         else
            local tversions = tp4:filelog(p4path.new(tt.depotFile, to))
            for ti,tv in ipairs(tversions) do
               local diff = p4.xdiff(args, { p4 = fp4, path =  fv}, { p4 = tp4, path = tv })
               if diff:len() == 0 then
                  --found baseline
                  if fi == 1 then
                     -- for fi == 0 latest from has already been merged
                     goto nextfile
                  else
                     p4.xmerge(args, tversions[ti], { p4 = fp4, path = fversions[1] },
                                                    { p4 = tp4, path = tversions[1] })
                     goto nextfile
                  end
               end
            end
         end
      end
      ::nextfile::
   end
end


----------------------------------------------------------------
-- scrub
----------------------------------------------------------------

function commands.scrub(args)
   local a = Actions:new {
      ['?'] = "rm",
      ['!'] = "sync",
      ['M'] = "sync",
      ["a"] = "revert",  -- one case where we can't pull to client
   }
   a.dirsUsed = {}
   a:compareFiles(args,"scrubView")
end

----------------------------------------------------------------
-- addremove
----------------------------------------------------------------

function commands.addremove(args)
   local a = Actions:new {
      ["?"] = "add",
      ["!"] = "delete",
      ["a"] = "revert",
      ["M"] = "edit",
      ["E"] = "trackEdit"
   }
   opts.force = opts.force or cfgData.addremoveNoConfirm

   a:compareFiles(args, "statusView", true)

   -- If we edited any files (or there were already) then revert -a
   if opts.force and (a.edit[1] or a.trackEdit[1]) then
      for _,dir in ipairs(a.dirs) do
         p4_x_( {"revert","-a"}, { dir:gsub("/$","").."/..."} )
      end
   end
end

----------------------------------------------------------------
-- status
----------------------------------------------------------------

function commands.status(args)
   local a = Actions:new{}
   local delim = opts.print0 and "\0" or "\n"
   function a:visitFile(f)
      if f.st ~= '.' then
         printf("%s %s%s", f.st, relpath(f.name), delim)
      end
   end
   function a:show() end
   a:compareFiles(args,"statusView")
end

----------------------------------------------------------------
-- find
----------------------------------------------------------------

function commands.find(args)
   if not args[1] then
      fatal("find: no file patterns given.")
   end
   local spec = tree.parseSpec(table.concat(args, "\n"), ".")

   local a = tree.findx(spec.roots, spec)

   local fmt = opts.print0 and "%s\0" or "%s\n"
   for _,f in ipairs(a) do
      printf(fmt, relpath(f.name, true))
   end
end

----------------------------------------------------------------
-- help
----------------------------------------------------------------

function commands.help(args)
   local topic = args[1] or "usage"
   local msg = helpText[topic]
   if not msg then
      fatal("unknown help topic [%s]", topic)
   end
   msg = string.gsub(msg, "P4X", progname)
   printf("%s\n", msg)
end

----------------------------------------------------------------
-- ls
----------------------------------------------------------------

local oldTime = os.time() - 180 * 24 * 60 * 60
local months = {
   "Jan", "Feb", "Mar", "Apr", "May", "Jun",
   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
}

local function lsDate(time)
   time = tonumber(time)
   if not time then
      return ""
   end
   local t = os.date("*t", time)
   if time < oldTime then
      return string.format("%s %2d  %4d", months[t.month], t.day, t.year)
   end
   return string.format("%s %2d %2d:%02d", months[t.month], t.day, t.hour, t.min)
end

local function doLS(dir)
   local dir, range = dir:match("([^@#]*)(.*)")
   local pattern = fsu.nix.resolve(dir, "*")..range

   -- pre-process files to auto-size columns (much nicer when
   -- the output consists entirely of directories)

   local files0 = p4fstat(pattern, {"-Ol", "-Os"}, true)
   local files = {}
   local maxSize = nil
   for _,t in ipairs(files0) do
      if t.headAction ~= "delete" then
         table.insert(files, t)
         local size = tonumber(t.fileSize)
         if size and size > (maxSize or 0) then
            maxSize = size
         end
      end
   end
   -- if there are dates/sizes, reserve a separator space also
   local dateWid = files[1] and 13 or 0
   local sizeWid = maxSize and 2+#tostring(maxSize) or 0

   -- display directories

   local dirs = p4dirs(pattern)
   local dirfmt = "d---------" .. string.rep(" ", dateWid+sizeWid) .. " %s\n"
   for _,d in ipairs(dirs) do
      local _, name = fsu.nix.splitpath(d)
      printf(dirfmt, name)
   end

   -- display files

   local filefmt = "%s-%s%"..sizeWid.."s%"..dateWid.."s %s\n"
   for _,t in ipairs(files) do
      local _, name = fsu.nix.splitpath(t.depotFile or "")
      local l, r, w, x, c, k, m, W, b, date, type
      type = t.headType or ""
      l = type:match("symlink") and "l" or "-"
      r = t.isMapped and "r" or "-"
      w = t.isMapped and t.action and "w" or "-"
      x = (type:match("^.?x") or type:match("+.-x")) and "x" or "-"
      b = (type:match("bin") or type:match("tempobj")) and "b" or
          type:match("apple") and "a" or
          type:match("uni") and "u" or
          type:match("utf16") and "U" or "-"
      m = type:match("+.-m") and "m" or "-"
      c = type:match("+.-C") and "c" or "-"
      W = type:match("+.-w") and "W" or "-"
      k = (type:match("^k") or type:match("+.-k")) and "k" or "-"
      date = lsDate(t.headTime or t.headModTime)
      printf(filefmt, l..r..w..x, c..k..m..W..b, t.fileSize or "?", date, name)
   end
end


function commands.ls(words)
   if words[2] then
      for _,dir in ipairs(words) do
         printf("%s:\n", dir)
         doLS(dir)
         printf("\n")
      end
   else
      doLS(words[1] or ".")
   end
end

----------------------------------------------------------------
-- version
----------------------------------------------------------------

function commands.version()
   commands.help({"version"})
end

----------------------------------------------------------------
-- command parameter handling
----------------------------------------------------------------

local optSpec = {
   "--force",
   "--new",
   "--verbose/-v",
   "--all",
   "--p4=",
   "--config=",
   "--log=",
   "--print0/-0",
   "--fromp4=",
   "--top4=",
   "--diff=",
   "--diff3=",
   "--merge=",
   "--resolve",
   "--resolvetool=",
}

local function main()
   local words
   words, opts = getopts.read(arg, optSpec, "exit")

   cfgData.file = config.find(opts.config or ".p4x", cfgData)

   if opts.verbose then
      addLogFile(io.stderr)
   end
   addLogFile(opts.log or cfgData.log)

   logf("* Command: %s|%s\n", tostring(arg[0]), table.concat(arg, "|"))
   if cfgData.file then
      logf("# using config file '%s'\n", cfgData.file)
   end

   p4Command = opts.p4 or cfgData.p4Command or "p4"
   local subcmd = table.remove(words, 1) or cfgData.default or "help"
   local cmdfn = commands[subcmd]
   if cmdfn then
      cmdfn(words, opts)
   else
      fatal("Unknown command.  Try '%s help' for info.", progname)
   end
end

-- Catch the errors we expect from bad user input and show a message.
-- Uncaught errors will show backtrace for debugging.
local ret = 0
local e = errors.catch( "tree: (.*),p4: (.*),(cannot open .*),exit: (.*),config: (.*)", main)
if e then
   printf("%s: %s\n", progname, e.values[1])
   ret = 1
end
if logFile then
   logf("# exit: %d\n", ret)
   logFile:close()
end

return ret
