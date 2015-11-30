-- pakman : package manager front-end
--
local helpText = {
usage = [=[
Usage:

   pakman get <URI>     : retrieve package(s)
   pakman map <URI>     : construct workspace, but do not sync
   pakman show <URI>    : show what pakman will sync
   pakman help options  : display command line option syntax
   pakman version       : display version information

]=],
options = [=[
pakman options:

    Options are order-independent and may be specified before or after
    other arguments.

    --config=<name>

          This specifies the name to use when looking for a config file,
          overriding the default name.  An empty file name ("--config=")
          causes pakman to use no config file.  See "pakman help config".

    --force

          This option causes Pakman to proceed in some situations that would
          ordinary result in a fatal error, such as a "depot conflict"
          error.

    --log=<file>

          This option directs pakman to log detailed information on the
          actions it performs to the specified file.

    --mapshort

          This sets the default mapping function to pmlib.mapShort.

    --p4=<command>

          This specifies the command name used by pakman to invoke the p4
          client.  The default is "p4".  This overrides any "p4.command"
          setting in the config file.

    --p4-sync=<flags>

          This modifies the behavior of p4 sync operations performed by
          Pakman.  <flags> is one or more flag characters to be passed to
          the Perforce command line tool.  For example, "--p4-sync=np"
          results in "p4 sync -n -p".  This option can appear multiple
          times on the command line to specify multiple p4 sync options.

    --verbose / -v

          This causes pakman to log detailed information to stdout.

    --version

          This displays version information (same as the "version"
          subcommand).

]=],
version = [=[
pakman <VER>
]=],
}


local fu = require "lfsu"
local PM = require "pm"
local Object = require "object"
local getopts = require "getopts"
local errors = require "errors"
local config = require "config"
local sysinfo = require "sysinfo"
local qt = require "qtest"
local pmlib = require "pmlib"

require "lua52" -- new os.execute, loadfile

local opts

-- Update version
local v = helpText.version
v = v:gsub("<VER>", sysinfo.versionStr)
helpText.version = v

-- config object for PM
local pmConfig = {}

pmConfig.hooks = {}
pmConfig.vcs = { p4 = {} }

-- construct environment for config files
local cfgEnv = {}
config.initEnv(cfgEnv)  -- defer to _G

cfgEnv.vcs    = pmConfig.vcs
cfgEnv.p4     = pmConfig.vcs.p4
--cfgEnv.pakman = pmConfig
cfgEnv.sys    = sysinfo
cfgEnv.pmlib  = pmlib

function cfgEnv.addHook(name, fn)
   pmConfig.hooks[name] = pmConfig.hooks[name] or {}
   table.insert( pmConfig.hooks[name], {fn = fn} )
end

cfgEnv.packagesLoaded = {}
function cfgEnv.require(name)
   if not cfgEnv.packagesLoaded[name] then
      local fn = assert(loadfile(name, nil, cfgEnv))
      cfgEnv.packagesLoaded[name] = fn()
   end
   return cfgEnv.packagesLoaded[name]
end

local commands = {}
local progname = (arg[0] or "pakman"):match("([^/\\]*)$")
if progname:match("%.") then
   progname = progname:match("(.*)%.")
end

----------------------------------------------------------------
-- Utility functions
----------------------------------------------------------------

----------------------------------------------------------------
-- Logging, etc.
----------------------------------------------------------------

local Logger = Object:new()

function Logger:initialize()
   self.outfiles = {}
end

function Logger:printF(...)
   if self.outfiles[1] then
      self:write( string.format(...) )
   end
end

function Logger:write(...)
   for _,fo in ipairs(self.outfiles) do
      fo:write( ... )
   end
end

function Logger:close()
   for _,fo in ipairs(self.outfiles) do
      fo:close()
   end
   self.outfiles = {}
end

function Logger:chain(file)
   if not file then return end

   if type(file) == "string" then
      local mode = "w"
      if file:sub(1,1) == "+" then
         file = file:sub(2)
         mode = "a+"
      end
      file = assert( io.open(file, mode) )
   end

   table.insert(self.outfiles, file)
   self.bActive = true
end

----------------------------------------------------------------

local log = Logger:new()

local function printf(...)
   io.write(string.format(...))
end

local function fatal(...)
   error("exit: " .. string.format(...))
end

----------------------------------------------------------------
-- help command
----------------------------------------------------------------

function commands.help(args)
   local topic = args[1] or "usage"
   local msg = helpText[topic]
   if not msg then
      fatal("unknown help topic [%s]", topic)
   end
   io.write(msg)
end

----------------------------------------------------------------
-- version command
----------------------------------------------------------------

function commands.version()
   commands.help({"version"})
end

----------------------------------------------------------------
-- get command
----------------------------------------------------------------

local function getPackages(args)
   local pkgs = {}
   local pm = PM:new(pmConfig)
   if not args[1] then
      args = { "." }
   end
   for _, pkg in ipairs(args) do
      printf("Getting %s\n", pkg)
      local pkg = pm:get(pkg)
      if opts.script then
         print("... fsRoot " .. pkg.fsRoot)
         print("... fsResult " .. pkg.fsResult)
         print("... treeMake " .. pkg.toMakeTree or "")
      end
      table.insert(pkgs, pkg)
   end
   return pkgs
end

function commands.get(args)
   getPackages(args)
end

----------------------------------------------------------------
-- make command
----------------------------------------------------------------

function commands.make(args)
   local err = 0
   local pkgs = getPackages(args)
   for _, pkg in ipairs(pkgs) do
      local cmd = pkg.toMakeTree -- expanded.commands.maketree
      if not cmd then
         pmConfig.stdout:printF("*** No command to make %s\n", pkg.uri)
      else
         pmConfig.stdout:printF("Making %s ...\n", pkg.uri)
         pmConfig.stdout:printF("Command: %s ...\n", cmd)
         -- We don't capture and log the output of the 'make' command; it
         -- writes directly to stdout/stderr.
         io.stdout:flush()
         io.stderr:flush()
         if fu.iswindows then
            cmd = '"' .. cmd .. '"'
         end
         local _
         _, _, err = os.execute(cmd)
         if err ~= 0 then break end
      end
   end
   return err
end

----------------------------------------------------------------
-- map command
----------------------------------------------------------------

function commands.map(args)
   local pm = PM:new(pmConfig)
   if not args[1] then
      args = { "." }
   end
   for _,pkg in ipairs(args) do
      printf("Mapping %s\n", pkg)
      pm:map(pkg)
   end
end

----------------------------------------------------------------
-- describe command
----------------------------------------------------------------

function commands.describe(args)
   local pm = PM:new(pmConfig)
   local p = pm:visit(args[1] or ".")

   local d = require "describe"
   d.describe(p)
end


----------------------------------------------------------------
-- visit command
----------------------------------------------------------------

function commands.visit(args)
   local pm = PM:new(pmConfig)
   if not args[1] then
      args = { "." }
   end
   for _,pkg in ipairs(args) do
      printf("Visiting %s\n", pkg)
      pm:visit(pkg)
   end
end


----------------------------------------------------------------
-- show command
----------------------------------------------------------------

function commands.show(args)
   local pm = PM:new(pmConfig)
   local cl
   if not args[1] then
      args = { "." }
   end
   for _,pkg in ipairs(args) do
      pm:show(pkg)
   end
end

----------------------------------------------------------------
-- main
----------------------------------------------------------------

local optStr = "--verbose/-v --p4= --config= --log= --script --p4-sync=* --mapshort --force --version"

local function main()
   local words
   words, opts = getopts.read(arg, optStr, "getopts")

   if opts.version then
      return commands.version()
   end

   pmConfig.file = config.find(opts.config or ".pakman", cfgEnv)
   pmConfig.verbose = cfgEnv.verbose or opts.verbose

   -- PM writes messages either to pmConfig.logFile or .stdout, so we set up
   -- cfg.stdout to chain to cfg.logFile (logFile gets all output), then:
   --   * io.stdout is chained from *either* cfg.stdout or cfg.log
   --   * other log files are chained from cfg.log

   pmConfig.logFile = log
   pmConfig.stdout = Logger:new()
   pmConfig.stdout:chain(log)
   local outfile = (pmConfig.verbose and log or pmConfig.stdout)
   outfile:chain( io.stdout )
   log:chain( opts.log or cfgEnv.log )

   log:printF("* %s", helpText.version)  -- no extra newline needed
   log:printF("* Command: %s|%s\n", tostring(arg[0]), table.concat(arg, "|"))
   if pmConfig.file then
      log:printF("# using config file '%s'\n", pmConfig.file)
   end

   for k, v in ipairs(cfgEnv.p4) do
      pmConfig.vcs.p4[k] = v
   end
   if opts.p4 then
      pmConfig.vcs.p4.command = opts.p4
   end

   pmConfig.vcs.p4.sync = (cfgEnv.p4 and cfgEnv.p4.sync) or opts["p4-sync"] or nil

   pmConfig.mapping = cfgEnv.mapping
   if opts.mapshort then
      pmConfig.mapping = pmlib.mapShort
   end

   pmConfig.force = opts.force

   log:printF("%s", qt.format("config data = %Q\n", pmConfig))

   local subcmd = table.remove(words, 1) or "help"
   local cmdfn = commands[subcmd]
   if cmdfn then
      return cmdfn(words)
   else
      fatal("Unknown subcommand '%s'.  Try '%s help' for info.", subcmd, progname)
   end
end

-- Catch the errors we expect from bad user input and show a message.
-- Uncaught errors will show backtrace for debugging.
local catches = os.getenv("pakman_catch") or
   "(pak): (.*),(exit): (.*),(getopts): (.*),(config): (.*),(pm): (.*),(p4): (.*),(fs): (.*)"

local e, ret = errors.catch(catches, main)
if e then
   if e.values[1] == "pak" then
      printf("%s\n", e.values[2])
   else
      printf("%s: %s\n", progname, e.values[2])
   end
   if e.values[1] == "config" then
      printf("    Try 'pakman help config --config=' for more information.\n")
   elseif e.values[1] == "getopts" then
      printf("    Try 'pakman help options' for more information.\n")
   end
   printf("pakman exited with error.\n")
   ret = 1
end

ret = ret or 0
if log then
   log:printF("# exit: %d\n", ret)
   log:close()
end
return ret
