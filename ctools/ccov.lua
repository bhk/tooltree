--
-- ccov : Command-line utility to read, merge, and output coverage data
--

local util = require "util"
local getopts = require "getopts"
local Cov = require "cov"
local version = require "ccov-ver"
local maxn = require "maxn"

local printf = util.printf
local fprintf = util.fprintf

local cmdName = string.match(arg[0], "([^%/%\\%.]+)%.?[^/\\]*$")

-- Describe command syntax
--
local function usage()
   io.write(cmdName .. [[ [options] files

    Read code coverage files and generate specified output.  If multiple
    input files are given their contents are merged.

    Input files can be in any of the following formats:

      * BullseyeCoverage CSV export files
      * ".gcov" output files
      * DevPartner XML export files
      * CCOV's native CSV file format (described below).

    Output formats are:

      * Default: a CSV file with all data read from input files.
      * Raw: a CSV file with only raw (non-derived fields)
      * Stats: a CSV file with statistics derived from raw data.
      * Listing: soure code annotated with coverage information.
        The default is gcov-style; Bullseye-style can be selected.

    Options:

       -h            : Output this summary.

       -v            : Print version and exit.

       -o <file>     : Specifies output file name.  "/dev/stdout" sends
                       output to stdout (the console) on all platforms.

       --verbose     : Selects verbose output.

       --raw         : Output raw data

       --stats       : Output stats derived from raw data.

       --list=<name> : Select listing for source file <name>.

       --style=<s>   : Specify listing style: "gcov" (default), or "be".

       --error       : Verify that all lines are covered in the source file
                       named using `--list`.  If coverage is complete, the
                       output file is created as an empty file.  Otherwise,
                       compiler-like error messages will be sent to stderr,
                       no output file is created, and the program will exit
                       with an error code.  [This currently applies only to
                       line coverage data; not Bullseye branch coverage.]

    Legacy options:

       -olct <file>  =  -o <file> --raw
       -ocsv <file>  =  -o <file> --stats
       -gcov <name>  =  --list <name> --style=gcov -o /dev/stdout
       -be <name>    =  --list <name> --style=be -o /dev/stdout

    CCOV uses an enhanced CSV file format for its native output and input
    files.  Initial lines beginning with "#" are considered metadata, and
    line containing "#csv <fieldnames>" is used to specify the names of
    fields and their ordering.  Field names are in comma-separated format.
    CCOV ignores field names it does not recognize, so coverage data can
    coexist with other data about source files.  See the CCOV sources for
    descriptions of the raw coverage data fields.

]])
   return 0
end

local function fail(fmt, ...)
   fprintf(io.stderr, cmdName .. ": " .. fmt .. "\n", ...)
   os.exit(1)
end

----------------------------------------------------------------
-- listings: source files annotated with coverage information
----------------------------------------------------------------

--------------------------------
-- Bullseye listing
--------------------------------

local function beEventText (symbol)
   if symbol:match("[onsN]") then
      return "--> "
   elseif symbol == "x" or symbol == "S" then
      return "X"
   elseif symbol == "y" then
      return "-->tf"
   elseif symbol == "Y" then
      return "-->TF"
   else
      return "-->"..symbol
   end
end

local function bePrintLine(fout, fileData, lineNo, text)
   local events = fileData and fileData.bdat and fileData.bdat[lineNo]

   local strformat = "%-7s%4d%-2s%s\n"
   if not events or #events == 0 then
      -- No line coverage data
      fprintf(fout, strformat, "", lineNo, "", text)
   elseif #events == 1 then
      -- Single-event line
      fprintf(fout, strformat, beEventText(events:sub(1,1)), lineNo, "", text)
   else
      -- Multi-event line
      fprintf(fout, strformat, beEventText(events:sub(1,1)), lineNo,"a", text)
      for i=2, #events do
         local ch = string.char(96+i)
         fprintf(fout, strformat, "  "..beEventText(events:sub(i,i)), lineNo, ch, "")
      end
   end
end

--------------------------------
-- gcov listing
--------------------------------

local function gcovPrintLine(fout, fileData, lineNo, text)
   local cnt
   if fileData then
      cnt = fileData.dat[lineNo]
   end
   local countField = (cnt==0 and "    #####") or tonumber(cnt) or "-"
   fprintf(fout, "%9s:%5d:%s\n", countField, lineNo, text)
end

--------------------------------
-- generic listing code
--------------------------------

local function writeListing(cov, fileName, listStyle, getOutFile, showErrors)
   -- get source file & its coverage data

   local fileData = cov:findFile(fileName)
   if not fileData then
      fail("Could not find coverage data for file [%s]", fileName)
   end

   local fsrc, err = io.open(fileData.file, "r")
   if not fsrc then
      fail("Could not open source file [%s]", fileData.file)
   end

   local printLine, covData
   if listStyle == "be" then
      printLine = bePrintLine
      covData = fileData.bdat
   else
      printLine = gcovPrintLine
      covData = fileData.dat
   end

   if not covData then
      fail("no coverage data for file: %s", fileName)
   end

   -- display errors for lines not covered

   if showErrors then
      local sawError
      for lineNo = 1, maxn(covData) do
         if covData[lineNo] == 0 then
            fprintf(io.stderr,
                    "%s:%d: error: line not executed\n",
                    fileData.file, lineNo)
            sawError = true
         end
      end
      if sawError then
         fail("Coverage errors seen")
      end
      getOutFile():close()
      return
   end

   -- open output file

   local fout = getOutFile()
   local sawError = false

   printLine(fout, nil, 0, "Source:" .. fileData.file)

   local lineNo = 0
   while true do
      lineNo = lineNo + 1
      local text = fsrc:read()
      if not text then
         break
      end
      local err = printLine(fout, fileData, lineNo, text)
      sawError = sawError or err
   end
   fsrc:close()
end

----------------------------------------------------------------
-- main
----------------------------------------------------------------


local MODE_DEFAULT = 1
local MODE_RAW = 2
local MODE_STATS = 3
local MODE_LIST = 4

-- Process arguments

local files, opts = getopts.read(arg,
                                 "-h -v -o= --verbose --error "
                                    .. " --raw --stats --list= --style="
                                    .. " -ocsv= -olct= -o= -gcov= -be=")

-- quick failure/exit cases

if not opts or not files then
   fail("Try -h for usage.")
elseif opts.v then
   printf("ccov %s\n", version)
   return 0
elseif opts.h then
   return usage()
elseif not files[1] then
   printf("No files to process.  Try -h for usage.\n")
   return 0
end


local settings = {}

local descriptions = {
   o = "output file",
   mode = "output format",
   style = "coverage listing style",
   list = "listing file name"
}


-- Handle cases where an option specifies or implies a setting; checking for
-- contradictions in options.  (Order of options should not matter.)
--
--   optName = option name on command line
--   settingName = member of settings[] to assign (if not optName)
--   value = if truthy, a value to override opts[optName]
--
local function assignSetting(optName, settingName, value)
   if not opts[optName] then return end

   settingName = settingName or optName
   value = value or opts[optName]

   local whoKey = settingName .. "_option"
   if settings[settingName] then
      fail("Option '%s' specifies %s, contradicting option '%s'",
           optName, descriptions[settingName] or settingName, settings[whoKey])
   end
   settings[settingName] = value
   settings[whoKey] = optName
end


assignSetting("o")

-- handle legacy options

for optName, mode in pairs{ olct = MODE_RAW, ocsv = MODE_STATS } do
   assignSetting(optName, "o")
   assignSetting(optName, "mode", mode)
end

for optName, style in pairs{ gcov="gcov", be="be" } do
   assignSetting(optName, "o", "/dev/stdout")
   assignSetting(optName, "mode", MODE_LIST)
   assignSetting(optName, "style", style)
   assignSetting(optName, "list")
end

-- end legacy options

if not settings.o then
   printf("%s: No output file specified.  Try -h for usage.\n", cmdName)
   return 0
end

assignSetting("raw", "mode", MODE_RAW)
assignSetting("stats", "mode", MODE_STATS)
assignSetting("list", "mode", MODE_LIST)
assignSetting("list")
assignSetting("style")


-- Read input files

local cov = Cov.new()
for _, fname in ipairs(files) do
   if opts.verbose then
      printf("Reading: %s\n", fname)
   end
   io.flush()
   local succ, e
   succ, e = cov:loadFile(fname)
   if not succ then
      fail("error processing input file: %s", e)
   end
end


-- Derive appropriate fields for each file
cov:deriveFields()

-- Output

local function getOutFile()
   local fileName = settings.o
   if fileName == "/dev/stdout" then
      return io.stdout
   end

   local f, err = io.open(fileName, "w")
   if not f then
      return fail("Error opening output file: %s", err)
   end
   return f
end


if settings.mode == MODE_LIST then

   writeListing(cov, settings.list, settings.style, getOutFile, opts.error)

else

   local hasLCT, hasBEC = cov:getTypes()
   local colNames
   if settings.mode == MODE_RAW then
      colNames = string.format( "file%s%s",
                                hasLCT and ",lct" or "",
                                hasBEC and ",bec" or "" )
   elseif settings.mode == MODE_STATS then
      colNames = string.format(
         "file%s%s",
         hasLCT and ",linesExecutable,linesExecuted,pctExecuted" or "",
         hasBEC and ",functTotal,functCov,condTotal,condCov" or "")
   else
      -- DEFAULT => write everything
   end

   local f = getOutFile()
   cov:fwrite(f, colNames)
   f:close()
end

for _,v in pairs(cov.warnings) do
   printf("%s: warning: %s", cmdName, v)
end
