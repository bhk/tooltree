----------------------------------------------------------------
-- smark: smart markup processor
----------------------------------------------------------------
local markup = require "markup"
local getopts = require "getopts"
local errors = require "errors"
local htmlgen = require "htmlgen"
local defaultCSS = require "defaultcss"
local doctree = require "doctree"
local smarkmisc = require "smarkmisc"
local Source = require "source"
local cmap = require "cmap"
-- @require smarkmacros  (for dependency scanning)

local E = doctree.E
local fatal = smarkmisc.fatal

local progname = (arg[0] or "smark"):match("([^/\\]*)$")

local versionStr = [[
smark 0.6
]]

local function readFile(name)
   return ( assert(smarkmisc.readFile(name), "exit: Could not read file: " .. name) )
end


-- Add SMARK_PATH to package.path.  When running in 'runlua' executable,
-- package.path will be empty (LUA_PATH is not honored).
--
local function setPath()
   local sp = os.getenv("SMARK_PATH") or "?.lua"
   package.path = sp:gsub(";$","") .. ";" .. package.path:gsub("^;", "")
end


local function openForWrite(fileName)
   local f = io.open(fileName, "w")
   if not f then
      fatal("Unable to open file %s for writing", fileName)
   end
   return f
end


local usageStr = [=[
Usage: smark [options] [<infile> -o <outfile>]

Options:
   --output=<file>
   -o <file>
       Write output to <file>.
   --out
       Write output to stdout.
   --in
       Read input from stdin.
   --deps=<file>
       Output a makefile that lists dependencies for the output file.
   --css=<file>
       Incorporate CSS style sheet into generated document.
   --no-default-css
       Do not include the default CSS in the generated document.
   --error
       Treat warnings as errors.
   --help
   -h
       Show this message.
   --version
   -v
       Display version number and exit.
]=]


local optionSpec = {
   "-h/--help",
   "-o/--output=",
   "--css=*",
   "--no-default-css",
   "-v/--version",
   "--config=",
   "--deps=",
   "--in",
   "--out",
   "--error"
}

local function main()
   if arg[1] == '-e' then
      -- Undocumented: '-e <file>' => local and execute lua file (use smark
      -- executable as a generic lua executable)
      table.remove(arg, 1)
      local fname = assert(table.remove(arg, 1), "-e: no file name given")
      return (assert(loadfile(fname)))()
   end

   local names, opts = getopts.read(arg, optionSpec, "exit")

   local cntInFiles = #names + (opts["in"] and 1 or 0)
   local cntOutFiles = #{opts.o} + #{opts.out}

   if opts.h then
      io.write(usageStr)
      return
   elseif opts.v then
      io.write(versionStr)
      return
   elseif cntInFiles < 1 then
      fatal("Input file not specified.  Try '%s -h' for help.", progname)
   elseif cntInFiles > 1 then
      fatal("Multiple input files specified.  Try '%s -h' for help.", progname)
   elseif cntOutFiles < 1 then
      fatal("Output file not specified.  Try '%s -h' for help.", progname)
   elseif cntOutFiles > 1 then
      fatal("Output file *and* stdout specified.  Try '%s -h' for help.", progname)
   end

   local configEnv = setmetatable({}, {__index = _G } )
   if opts.config then
      local f = assert(loadfile(opts.config, nil, configEnv))
      f()
   end

   setPath()

   local data = opts["in"] and io.read("*a")
   local source = Source:new():newFile(names[1], data)
   local doctree = markup.parseDoc(source)
   doctree = markup.expandDoc( doctree, configEnv )

   -- prepend default CSS and/or specified CSS files
   local sheets = {}
   if not opts["no-default-css"] then
      sheets = { defaultCSS }
   end
   for _, name in ipairs(opts.css or {}) do
      source:addFile(name)
      table.insert(sheets, readFile(name))
   end
   local css = E.style{ type="text/css", table.concat(sheets, "\n") }
   table.insert(doctree, 1, E.head{ css } )

   -- append default for title (any earlier title node will "win")
   table.insert(doctree, E.head{ E.title{ opts.o } } )

   -- If "--error" and warnings, then error out before writing output files
   if source.didWarn and opts.error then
      return fatal("Warnings treated as errors")
   end

   local html = htmlgen.generateDoc(doctree)

   -- output HTML
   local fo = opts.out and io.stdout or openForWrite(opts.o)
   fo:write(html)
   fo:close()

   -- output dependencies
   if opts.deps then
      local fd = openForWrite(opts.deps)
      if source.files[1] then
         -- omit the initial file (not an implicit dependency)
         local deps = table.concat(source.files, " ", 2)
         fd:write(opts.o .. ": " .. deps .. "\n\n")
      end

      -- add an empty rule for each file other than the main one
      -- (a la 'gcc -M -MP')
      for n = 2, #source.files do
         fd:write(source.files[n] .. ":\n\n")
      end
      fd:close()
   end

   return 0
end

--------------------------------
-- run program
--------------------------------

local e  = errors.catch("exit: (.*)", main)
if e then
   io.stderr:write(progname .. ": " .. e.values[1] .. "\n")
end
return e and 1 or 0
