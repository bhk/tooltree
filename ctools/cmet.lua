-- #!/usr/bin/env lua
-- See bottom of file for usage.

local U = require "util"
local csv = require "csv"
local fez = require "fez"
local getopts = require "getopts"
local version = require "cmet-ver"

local printf = U.printf
local function fprintf(f, ...)
   f:write(string.format(...))
end

----------------------------------------------------------------
-- Utilities
----------------------------------------------------------------

local tests = {}   -- add tests here to be executed with "-t"

local cmdName = string.match(arg[0], "([^%/%\\%.]+)%.?[^/\\]*$")

-- Associate instance with class, or class with superclass
local function setParent(tbl, parent)
   return setmetatable(tbl, { __index = parent } )
end


local function fassert(val, fname)
   if val == nil then
      printf("%s: could not open file: %s\n", cmdName, fname)
      os.exit(-1)
   end
end


-- Portability problem: Lua's input/output of 'nan' and 'inf' is inconsistent
--   because it builds on ANSI C and MSVC's implementation does not match
--   MacOS and Cygwin.  This affects tonumber() and string.format().
--
local _tonumber = tonumber
function tonumber(e,b)
   local n = _tonumber(e,b)
   if n and type(e) == "string" and e:match("^ *([iInN][nNaA][fFnN]) *$") then
      n = nil
   end
   return n
end


----------------------------------------------------------------
-- DB class
--
-- Each DB oject is an array of rows, and supports the following methods:
--
--   #obj         : gives number of rows
--   obj[n]       : gives row n
--   obj:add()    : adds row to database
--   obj:find()   : finds row
--   obj:index()  : creates index
--   obj:select() : select rows & columns
--
-- NOTE: Modifying the contents of a row when it resides in a database
-- can corrupt indices.  Treat rows as read-only.
--
----------------------------------------------------------------

local DB = {}


function DB.new()
   local me = {}
   setParent(me, DB)
   me.indices = {}
   return me
end


-- Create an index for a field; regenerate if already there.
-- The index created accelerates 'find'.
--
function DB:index(field)
   local index = {}
   for _,row in ipairs(self) do
      index[row[field]] = row
   end
   self.indices[field] = index
end


function DB:isDuplicate(row)
   for _,r in ipairs(self) do
      if U.tableEQ(row, r) then
	 return true
      end
   end
   return false
end


-- Add a row to the database
--
function DB:add(row, bUnique)
   if bUnique and self:isDuplicate(row) then
      return nil
   end
   table.insert(self, row)
   for field,index in pairs(self.indices) do
      index[row[field]] = row
   end
   return row
end


-- Find a row for which row[keyfield] == keyvalue.
-- If there are multiple matches, only one is returned.
--
-- NOTE: This returns a reference to the row that resides in the database.
--
function DB:find(keyfield, keyvalue)
   local index = self.indices[keyfield]
   if index then
      return index[keyvalue]
   end
   -- linear search
   for _,row in ipairs(self) do
      if row[keyfield] == keyvalue then
	 return row
      end
   end
   return nil  -- not found
end


local function dupRow(row, fields)
   local new = {}
   if fields then
      for _,fld in ipairs(fields) do
	 new[fld] = row[fld]
      end
   else
      for k,v in pairs(row) do
	 new[k] = v
      end
   end
   return new
end


function tests.dupRow()
   local fields = { "a", "b", "c", "end"}
   local row = {}
   for _,fld in ipairs(fields) do
      assert( U.tableEQ(row, dupRow(row)) )
      assert( U.tableEQ(row, dupRow(row, {"a", "b", "c"})) )
      row[fld] = fld..fld
   end
   assert( U.tableEQ( {a=1,b=2},  dupRow({3,4,a=1,b=2,c=5}, {'a','b'}) ) )
end


-- Return selected rows and columns
--   pred = true for all rows; function to test a row for inclusion otherwise
--   fields = array of fields to select, or nil for all
--   bUnique = true if result table should consist of unique rows
--
function DB:select(pred, fields, bUnique)
   local fn = pred
   if pred == true then
      fn = function () return true end
   end
   local result = DB.new()
   for _,row in ipairs(self) do
      if fn(row) then
	 result:add(dupRow(row, fields), bUnique)
      end
   end
   return result
end


-- Return an array of field names, and a truth table (t[field] => used)
--
function DB:getFieldNames()
   local tNames = {}
   local tIdx = {}
   for _,row in ipairs(self) do
      for k,_ in pairs(row) do
	 if not tIdx[k] then
	    tIdx[k] = true
	    table.insert(tNames, k)
	 end
      end
   end
   return tNames, tIdx
end


function tests.DB()
   local db = DB.new()

   db:add{a=1, b=2, c=3}
   db:add{a=4, b=5, c=6}
   db:index("a")
   db:add{a=7, b=8, c=9}

   assert( db:find('a', 1)['b'] == 2 )
   assert( db:find('a', 4)['b'] == 5 )
   assert( db:find('a', 7)['b'] == 8 )

   assert( db:find('b', 2)['a'] == 1 )
   assert( db:find('b', 5)['a'] == 4 )
   assert( db:find('b', 8)['a'] == 7 )
end


----------------------------------------------------------------
-- Formatter class
--
-- Each Formatter instance contains an array of FormatCol values,
-- one for each column of output.
--
-- Each entry contains:
--     key = key for value in the table
--     fmt = printf-style format string for formatting value
--     hdr = short description for the header line
--
--  Example entry:
--     { key="L",  fmt="%-20s",  hdr="Lines"}
--
----------------------------------------------------------------


-- FormatCol constructor
--
local function FormatCol(name, hdr, fmt, desc, dflt, fn)
   return {
      name=name, hdr=hdr, fmt=fmt, desc=desc, isDefault=dflt, fn=fn,
      isNumeric = fmt:match("[idufg]") ~= nil
   }
end


-- Eaach Formatter contains formatting information:
--    self[1...n] = fields (FormatCol) in order of printing
--
local Formatter = {}
setParent(Formatter, DB)


function Formatter.new()
   local me = DB.new()
   setParent(me, Formatter)
   me:index("hdr")
   return me
end


function Formatter:findCol(name)
   return self:find("name", name) or self:find("hdr", name)
end


-- Initialize the array of fields to be formatted
--
--   str = comman-separated list of field names, or nil
--   format = Formatter instance that names all available fields
--   db = database to be formatted
--
function Formatter:setFields(str, format, db)
   if str then
      -- Use fields named in str
      for f in str:gmatch("[^,]+") do
	 local col = format:findCol(f)
	 if col then
	    table.insert(self, col)
	 end
      end
   else
      -- Use all default fields that are present in the db
      local _,tIdx = db:getFieldNames()
      for _,col in ipairs(format) do
	 if tIdx[col.name] and col.isDefault then
	    table.insert(self, col)
	 end
      end
   end
end


function Formatter:printLegend()
   for _,fld in ipairs(self) do
      printf("%10s = %s\n", fld.hdr, fld.desc)
   end
   io.write("\n")
end

local function colFormat(col, val)
   local fmt = col.fmt
   if not val then
      val = "n/a"
   end
   if col.isNumeric and not tonumber(val) then
      fmt = fmt:match("(%%[^%.iudcsfg]*)") .. "s"
   end
	if col.isNumeric and (val ~= val) then
      return fmt:gsub("[idufg]$", "s"):format("n/a")
   end
   return fmt:format(val)
end


local function rtrim(str)
   return str:match("^(.-)%s*$")
end


function tests.rtrim()
   assert( rtrim("ab  ") == "ab")
   assert( rtrim("a b  ") == "a b")
   assert( rtrim("a  b ") == "a  b")
   assert( rtrim(" a b ") == " a b")
end

-- Print formatted headers
--
function Formatter:printHeader()
   local str = ""
   for _,col in ipairs(self) do
      str = str .. colFormat(col, col.hdr) .. " "
   end
   io.write( rtrim(str) .. "\n" )
end


-- Print formatted row
--   nAverage = no. by which to divide all numeric fields
--
function Formatter:printRow(row, nAverage)
   local str = ""
   local div = nAverage or 1

   for _,col in ipairs(self) do
      local fmt = col.fmt
      local val = row[col.name]

      if col.fn then
	 val = col.fn(row, nAverage)
      elseif col.isNumeric then
	 val = tonumber(val) and val/div
      end

      str = str .. colFormat(col, val) .. " "
   end

   io.write( rtrim(str) .. "\n" )
end


-- Print row (containing totals) plus a count-normalized version (averages)
--
function Formatter:printTotal(rec, count, name)
   if tonumber(count) and count > 0 then
      rec.name = string.format("%s Total (%d)", name, count)
      self:printRow(rec)
      rec.name = string.format("%s Average", name)
      self:printRow(rec, count)
      io.write("\n")
   end
end


-- Output a line of text
--
function Formatter:printf(...)
   printf(...)
end


-- Get sort details from sort string:  [-] FIELDNAME [: MAX]
--
local function parseSortString(sortstr, fmtFields)
   local dir, fld, max = sortstr:match("(%-?)(%a*)%:?(%d*)")
   max = tonumber(max)

   local fldrec = fmtFields:findCol(fld)
   if fldrec then
      fld = fldrec.name
   end

   local cmp, desc

   if dir == "-" then
      cmp = function (a,b) return a > b end
      desc = "Highest"
   else
      cmp = function (a,b) return a < b end
      desc = "Lowest"
   end
   desc = desc .. " " .. fld

   local typify = tostring
   if fldrec and fldrec.isNumeric then
      typify = tonumber
   end

   local function sortfn(a,b)
      local va, vb = typify(a[fld]), typify(b[fld])
      return va and ( (not vb) or cmp(va,vb) )
   end

   return sortfn, max, desc
end


local function accumRow(totals, samples)
   for k,v in pairs(samples) do
      if totals[k] ~= "n/a" then
         local n = tonumber(v)
         if n then
            totals[k] = n + (tonumber(totals[k]) or 0)
         else
            totals[k] = "n/a"
         end
      end
   end
   totals.cnt = (totals.cnt or 0) + 1
end



-- Print formatted table
--
function Formatter:printTable(dbIn, opts, fmtFields)
   local max, sortDesc
   local function sortFn(a,b)
      local ag = tostring(a.group)
      local bg = tostring(b.group)
      return ag < bg or (ag == bg and tostring(a.name) < tostring(b.name))
   end

   -- Output group totals at transitions between different groups
   --
   local groupTotal, groupName = nil, nil
   local function group(row)
      local thisgrp = row and row.group
      if thisgrp ~= groupName then
	 if groupTotal then
	    self:printTotal(groupTotal, groupTotal.cnt, groupName..":")
	 end
	 groupName = thisgrp
	 groupTotal = { name = groupName }
      end
      if row and groupTotal then
	 accumRow(groupTotal, row)
      end
   end

   -- select those with a group and name
   local db = dbIn:select(function (row) return row.group and row.group ~= "" and row.name end)
   if #db == 0 then
      db = dbIn  -- no 'group' attributes ... use all records
   end

   self:setFields(opts.fields, fmtFields, db)    -- formatting info

   -- Sort/group rows
   if opts.sort then
      sortFn, max, sortDesc = parseSortString(opts.sort, fmtFields)
      group = function () end   -- disable grouping
      self:printf("Sort: %s\n\n", sortDesc)
   end
   table.sort(db, sortFn)

   -- Print rows
   local total = {}

   self:printHeader()

   for ndx,row in ipairs(db) do
      if max and ndx > max then break end
      group(row)
      self:printRow(row)
      accumRow(total, row)
   end

   group()
   self:printHeader()
   self:printTotal(total, total.cnt, "Overall")

   self:printLegend()
end


----------------------------------------------------------------
-- Generic read/merge/format logic
----------------------------------------------------------------

-- Each application must provide the following:
--   - Add available fields to allFields
--   - Set keyField string
--   - Define postProcess function
--
local keyField                      -- key field
local allFields = Formatter.new()   -- fields available for formatting
local postProcess                   -- function to post-process a table


-- Return function that iterates over all records in db that match records
-- in tbl (creating matching db records as necessary).  Iterator
-- returns:  db_record, tbl_record
--
local function enumMatchedRecords(db, tbl)
   local iter = U.ivalues(tbl)
   return function ()
	     repeat
		local row = iter()
		local key = row and row[keyField]
		if key then
		   local rec = db:find(keyField, key)
		   if not rec then
		      rec = db:add{ [keyField] = key }
		   end
		   return rec, row
		end
	     until row == nil end
end


-- Merge row from 'src' into database 'db'
--
local function mergeTable(db, src)
   for rec, row in enumMatchedRecords(db, src) do
      -- todo: optionally warn about conflicting overrides

      -- Note: modifying record in-place (could invalidate indices)
      for k,v in pairs(row) do
	 rec[k] = v
      end
   end
end


-- Merge row from 'src' into database 'db'
--
local function subtractTable(db, fname)
   local t = csv.loadFile(fname)
   fassert(t, fname)
   t = postProcess(t)

   for drec, srec in enumMatchedRecords(db, t) do
      for k,v in pairs(srec) do
	 local n = tonumber(v)
	 if n then
	    drec[k] = (tonumber(drec[k]) or 0) - n
	 end
      end
   end
end


-- Read input files and derive fields
--
local function readTables(files)
   local stats = DB.new()
   stats:index(keyField)

   for _,f in ipairs(files) do
      local t = csv.loadFile(f)
      fassert(t, f)
      t = postProcess(t)
      mergeTable(stats, t)
   end

   return stats
end


-- Print database
--
local function formatTable(db, opts)
   local fmt = Formatter.new()
   fmt:printTable(db, opts, allFields)
end


-- Output table
--
local function saveTable(db, opts)
   local fieldnames = db:getFieldNames()
   table.sort(fieldnames)

   if opts.fields then
      -- Look up column by actual CSV name or header text
      fieldnames = {}
      for _,name in ipairs(U.stringSplit(opts.fields, ",")) do
	 local col = allFields:findCol(name)
	 if col then
	    table.insert(fieldnames, col.name)
	 else
	    table.insert(fieldnames, name)
	 end
      end
   end

   local f = io.open(opts.o, "w")
   fassert(f, opts.o)
   csv.writeFile(f, db, table.concat(fieldnames, ","))
   f:close()
end


----------------------------------------------------------------
-- Application-specific logic (Source Code Metrics)
----------------------------------------------------------------

keyField = "cpath"

local function field(...)
   allFields:add(FormatCol(...))
end

field("file",             "File",      "%-64s", "Complete path for source file")
field("bytes",            "Bytes",     "%8d",  "File size in bytes")
field("lines",            "Lines",     "%6d",  "File size in lines (simple line count)", true)
field("ploc",             "PLOC",      "%6d",  "Program Lines of Code (ignores blank and comment lines)", true)
field("icount",           "iCount",    "%6d",  "Number of included headers (direct and indirect)")
field("ibytes",           "iBytes",    "%9d",  "Number of bytes in included headers")
field("ilines",           "iLines",    "%7d",  "Number of lines in included headers")
field("iploc",            "iPLOC",     "%6d",  "PLOC in all included header files", true)
field("rom",              "ROM",       "%6d",  "ROM footprint", true)
field("ram",              "RAM",       "%6d",  "RAM footprint (static)", true)
field("roData",           "ROData",    "%6d",  "RO Data Size")
field("rwData",           "RWData",    "%6d",  "RW Data Size")
field("ziData",           "ZIData",    "%6d",  "ZI Data Size")
field("linesExecutable",  "CovLns",    "%6d",  "Executable lines of code (for coverage)", true)
field("linesExecuted",    "CovExe",    "%6d",  "Executable lines covered in coverage tests")
field("linesNotExecuted", "CovNot",    "%6d",  "Executable lines not covered in coverage tests", true)
field("pctExecuted",      "CovPct",    "%6d",  "Percentage of lines of code executed", true,
	 -- Calculated fields are recalculated for average (not simply averaged)
	 function (m)
	    local cl = tonumber(m.linesExecutable)
	    if cl and cl > 0 then return m.linesExecuted * 100 / cl end
	 end)
field("name",             "Name",      "%-28s", "Source file name", true)
field("cpath",            "CPath",     "%-28s", "Canonical path for source file")
field("group",            "Group",     "%-12s", "Group name")
field("fez",              "FEZ",       "%-28s", "FEZ File")
field("functTotal",       "FctTot",    "%6d",   "Number of function declerations present")
field("functCov",         "FctCov",    "%6d",   "Number of functions called at least once")
field("functNotCov",      "FctNoCov",  "%8d",   "Number of functions never called", true)
field("functPctCov",      "FctPctCov", "%9d",   "Percentage of functions covered", true,
	 -- Calculated fields are recalculated for average (not simply averaged)
	 function (m)
	    local funct = tonumber(m.functTotal)
	    if funct and funct > 0 then return m.functCov * 100 / funct end
	 end)
field("condTotal",        "CndTot",    "%6d",   "Number of coditions/decisions")
field("condCov",          "CndCov",    "%6d",   "Number of coditions/decisions fully covered (evaluated to both true and false)")
field("condNotCov",       "CndNoCov",  "%8d",   "Number of coditions/decisions not/partially covered", true)
field("condPctCov",       "CndPctCov", "%9d",   "Percentage of coditions/decisions fully covered", true,
	 -- Calculated fields are recalculated for average (not simply averaged)
	 function (m)
	    local cond = tonumber(m.condTotal)
	    if cond and cond > 0 then return m.condCov * 100 / cond end
	 end)


-- Remove drive letter and normalize slashes
--
local function unixifyPath(path)
   if path then
      path = path:gsub("\\", "/")
      path = path:match("^%w%:(/.*)") or path
   end
   return path
end


-- Convert to lower-case; remove drive letter; convert slashes to "/"
--
local function getCPath(path, cwd)
   if not path or path == "" then return nil end
   path = U.ResolvePath(unixifyPath(cwd), unixifyPath(path))
   return path:lower()
end


function tests.getCPath()
   assert( getCPath(nil) == nil )
   assert( getCPath("/a/B/c")      == "/a/b/c" )
   assert( getCPath("c:\\A\\b\\c") == "/a/b/c" )
   assert( getCPath("E:\\a\\b\\C") == "/a/b/c" )
   assert( getCPath("E:\\a\\b\\C", "/dir/") == "/a/b/c" )
   assert( getCPath("a\\b\\C", "/dir/") == "/dir/a/b/c" )
   assert( getCPath("a\\b\\C", "/dir") == "/dir/a/b/c" )
   assert( getCPath("\\\\unc\\a", "/dir") == "//unc/a" )
end


-- Derive fields for source code metrics
--
-- postProcess() may return a new table or modify and return the input table
--
function postProcess(table)
   local function setif(row,fld,val)
      if row[fld] == nil then row[fld] = val end
   end

   for _,row in ipairs(table) do
      local cpath = row.cpath or getCPath(row.file, row.cwd)
      if cpath then

	 -- name and path

	 row.cpath = cpath
	 local fname = row.file or row.cpath   -- use case-preserving .file if present
	 row.name = row.name or fname:match("[^/\\]*$")

	 local cl = tonumber(row.linesExecutable)
	 if cl then
	    -- Derive from:  cl = linesExecuted + linesNotExecuted

	    if not row.linesNotExecuted and tonumber(row.linesExecuted) then
	       row.linesNotExecuted = cl - row.linesExecuted
	    elseif not row.linesExecuted and tonumber(row.linesNotExecuted) then
	       row.linesExecuted = cl - row.linesNotExecuted
	    end
	    if not row.pctExecuted and tonumber(row.linesExecuted) then
	       row.pctExecuted = row.linesExecuted * 100 / cl
	    end
	 end

    local fnct = tonumber(row.functTotal)
	 if fnct then
	    -- Derive from:  functTotal = functCov + functNotCov

	    if not row.functNotCov and tonumber(row.functCov) then
	       row.functNotCov =fnct - row.functCov
	    elseif not row.functCov and tonumber(row.functNotCov) then
	       row.functCov = fnct - row.functNotCov
	    end
	    if not row.functPctCov and tonumber(row.functCov) then
         row.functPctCov = (fnct==0 and 0) or (row.functCov * 100 / fnct)
	    end
	 end

    local cond = tonumber(row.condTotal)
	 if cond then
	    -- Derive from:  condTotal = condCov + condNotCov

	    if not row.condNotCov and tonumber(row.condCov) then
	       row.condNotCov =cond - row.condCov
	    elseif not row.condCov and tonumber(row.condNotCov) then
	       row.condCov = cond - row.condNotCov
	    end
	    if not row.condPctCov and tonumber(row.condCov) then
	       row.condPctCov = (cond==0 and 0) or (row.condCov * 100 / cond)
	    end
	 end

	 if row.fez and not (row.rom and row.ram and row.roData and row.rwData and row.ziData) then
	    local f = io.open(row.fez)
	    if f then
	       local rom, ram, code, d, roData, rwData, ziData = fez.read(f:read("*a"))
	       setif(row, "rom", rom)
	       setif(row, "ram", ram)
	       setif(row, "roData", roData)
	       setif(row, "rwData", rwData)
	       setif(row, "ziData", ziData)
	       f:close()

	       if not rom then
		  fprintf(io.stderr, "cmet: warning: file format not recognized [%s]\n", row.fez)
	       end
	    else
	       fprintf(io.stderr, "cmet: warning: could not open file [%s]\n", row.fez)
	    end
	 end
      end
   end
   return table
end


------------------------------------------------
-- Main
------------------------------------------------

local function usage()
   io.write(cmdName .. [[
 [options] files

  All files are read, merged into one data set, and output as specified by
  command options.  Use '-h2' for more information on input files.

  Options:
    -h or --help : Output this message.

    -h2 : Describe input file format.

    -h3 : Describe derived fields.

    -v / --version : Display version of cmet and exit.

    -fields <fields> : Output specified fields.  <fields> is a comma-
                       separated list of field names or column headers.

    -sort <sort> : Output a sorted listing.  <sort> is a field name, with an
                   optional "-" prefix to indicate decreasing values, and an
                   an optional ":max" suffix giving the number of results.

    -o <file>    : Output merged data to a new data file (modified CSV).

    -delta <file> : Subtract values in <file> from the merged data set.

]])
end


local function usage2()
   io.write([[
  Input files are in a modified CSV format.  Each line represents a row of a
  table, except for lines beginning with "#" which contain metadata.  Metadata
  lines should precede data lines.  The file must include a metadata line
  naming the fields in each data line.  It has the following format:

      #csv field1,field2,...

  If a field takes the same value in all rows it can be omitted from the
  data lines and instead represented using:

      #set field=value

  Every row describes a source file, and should have a 'file' field that
  names the source file described by the table.  The table merge operation
  uses a canonicalized form of this value as a key field in order to be
  tolerant of case and slash/backslash differences.

  A 'group' field controls grouping of files in the formatted output.  Files
  that have a zero-length group name (or no group at all) are not printed.

  Below are all supported field names with the column heading and description
  for each:

]])

   for _,fld in ipairs(allFields) do
      printf('%18s = %s: %s\n', fld.name, fld.hdr, fld.desc)
   end
   io.write("\n")
end


local function usage3()
   printf([[

  %s will derive some fields, but only when they are not provided in
  the input files and there is enough other information avaiable.

    Field(s)                Can be derived from...
   --------------------    ------------------------------------------
    name                    file or cpath

    linesNotExecuted        linesExecutable & linesExecuted

    linesExecuted           linesExecutable & linesNotExecuted

    pctExecuted             linesExecutable & linesExecuted

    rom, ram, roData,       fez
    rwData, or ziData

    functNotCov             functTotal & functCov

    functPctCov             functTotal & functCov

    condNotCov              condTotal & condCov

    condPctCov              condTotal & condCov

  When 'name' is derived, it is set to the last path element of 'file'
  or 'cpath' (dropping the directory part of the path).

  The field 'fez' specifies the name of a file that describes the object
  file contents.  This 'fez' file will be read and parsed to obtain size
  statistics.  It should contain the output of one of these commands:

    fromelf -z <object>           : ARM ADS
    size <object>                 : UNIX and kindred tool chains
    dumpbin /headers <object>     : Microsoft

]], cmdName)
end


local files, opts = getopts.read(arg, "-v/--version --verbose -h -h2 -h3 -t -h/--help -fields/-f/--fields= -sort= -cov= -o= -delta=")

if opts.v then
   printf("cmet %s\n", version)
   return 0
elseif not files then
   printf("Try '%s -h' for usage.\n", cmdName)
   os.exit(-1)
end

if opts.t then
   for name, testfunc in pairs(tests) do
      print("Test: " .. name)
      testfunc()
   end
end

if opts.h then
   usage()
elseif opts.h2 then
   usage2()
elseif opts.h3 then
   usage3()
elseif not files[1] then
   printf("No files to process; try '%s -h' for options.\n", cmdName)
else

   local db = readTables(files)

   if opts.delta then
      subtractTable(db, opts.delta)
   end

   if opts.o then
      saveTable(db, opts)
   else
      formatTable(db, opts)
   end
end
