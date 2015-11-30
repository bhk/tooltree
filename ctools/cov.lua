-- cov : Implements Cov class for reading/writing coverage data
--

local util = require "util"
local csv = require "csv"
local xml = require "xml"
local maxn = require "maxn"

local Cov = {}

local CovMT = { __index = Cov }


-- Create a new instance of Cov
--
-- self[1...n ] = row
--
--    row.file = file name
--
--    row.lct = line counts string
--
--    row.dat = execution counts:  <line_num> -> <execution_count>
--              Only executable lines map to numbers; non-executable
--              lines map to nil (i.e. are absent from the table).
--
--    row.bdat = bullseye events:  <line_num> -> <eventString>
--               <eventString> is a string of single-char event codes.
--               An empty string represents non-executable lines.
--
-- self.indices[f]  ->  row with file==f
--
function Cov.new()
   local me = {
      indices = { file = {} },
      warnings = {}
   }
   setmetatable(me, CovMT)
   return me
end


function Cov:warn(str)
   table.insert(self.warnings, str)
end


-- Find/create a row for `fileName`, and then find/create field
-- `fieldName` within that row.  The field is initialzed to an
-- empty table if it does not already exist.
--
--
function Cov:getFileTable(fileName, fieldName)
   -- Find file record, or create new record if necessary
   fileName = util.CleanPath(fileName)

   local row = self.indices.file[fileName]
   if not row then
      row = { file = fileName}
      table.insert(self, row)
      self.indices.file[fileName] = row
   end

   -- Return requested field or create new field if necessary
   if not row[fieldName] then
      row[fieldName] = {}
   end
   return row[fieldName]
end


-- Does 'name' match any relative or absolute part of 'path' ?
--
function Cov.fileMatches(name, path)
   local function fcanon(path)
      path = path:lower()
      path = path:gsub("\\", "/")
      return path:match("^%w%:(/.*)") or path
   end

   local a,b = fcanon(name), fcanon(path)
   return a == b or util.stringEnds(b, "/"..a)
end


-- Find any matching file
--
function Cov:findFile(file)
   for _,row in ipairs(self) do
      if Cov.fileMatches(file, row.file) then
         return row
      end
   end
end


----------------------------------------------------------------------------
-- DevPartner XML coverage files
----------------------------------------------------------------------------

-- The relevant parts of the document are described by dpcovMap, which
-- maps out the subset of the document that we want to capture in the DOM
-- tree:

local dpcovMap = {
   sessionFile = xml.ByName {
      images = xml.ByName {
         image = {
            name = xml.ByName {},
            sourceFile = {
               path         = xml.STRING,
               coverageData = xml.ByName( xml.CaptureAll() ),
               ["function"] = {
                  name = xml.STRING,
                  sourceLineData = xml.ByName {
                     line = {}
                  },
               },
            }
         }
      }
   }
}


-- Accumulate coverage stats from DPXML file
--
function Cov:loadDPXML(text)
   local dom, msg = xml.DOM(text, dpcovMap)
   if not dom then
      return nil, msg
   end

   local images = dom.sessionFile and dom.sessionFile.images
   if not images then
      self:warn("loaded DPXML file contains no <images>")
      return true
   end

   for _,img in ipairs(dom.sessionFile.images) do
      for _,src in ipairs(img) do

         -- 'sourceFile' element

         if not src.path then
            return nil, "Bad DPXML file: <path> not in <image>"
         end

         local dat = self:getFileTable(src.path,"dat")

         for _,fn in ipairs(src) do

            -- 'function' element
            if not fn.sourceLineData then
               return nil, "Bad DPXML file: <sourceLineData> not in <function>"
            end

            for _,line in ipairs(fn.sourceLineData) do

               -- 'sourceLineData' element => executable line

               local n = tonumber(line.number)
               dat[n] = (dat[n] or 0) + tonumber(line.executionCount)
            end
         end
      end
   end

   return true
end


----------------------------------------------------------------------------
-- Bullseye Coverage Files
----------------------------------------------------------------------------

-- bullseyeMergeTbl acts as a function that merges two event strings
-- and memoizes the results:
--
--     mergeTbl[c1..c2]       ->  merge of two event codes
--     mergeTbl[s1.."_"..s2]  ->  merge of two event strings
--
-- Internal codes for Bullseye events:
--
--    o - function not called
--    x - function called
--    n - condition not covered
--    t - condition evaluated to true but not false
--    f - condition evaluated to false but not true
--    y - condition evaluated to both true and false
--    N - decision not covered
--    T - decision evaluated to true but not false
--    F - decision evaluated to false but not true
--    Y - decision evaluated to both true and false
--    S - switch statement executed
--    s - switch statement not executed
--
local bullseyeMergeTbl = {
   nn="n", nt="t", nf="f", ny="y",
   tn="t", tt="t", tf="y", ty="y",
   fn="f", ft="y", ff="f", fy="y",
   yn="y", yt="y", yf="y", yy="y",
   NN="N", NT="T", NF="F", NY="Y",
   TN="T", TT="T", TF="Y", TY="Y",
   FN="F", FT="Y", FF="F", FY="Y",
   YN="Y", YT="Y", YF="Y", YY="Y",
   ox="x", oo="o",
   xo="x", xx="x",
   sS="S", ss="s",
   Ss="S", SS="S",
}

local _BullseyeMergeTbl = {}

-- We assume that all lookups (aside from the above pre-populated results)
-- are of the form <s1>_<s2>, where <s1> and <s2> are of the same length.
--
function _BullseyeMergeTbl:__index(s)
   local res
   local a1,ax,b1,bx = s:match("^([^_])([^_]*_)(.)(.*)$")
   if a1 then
      res = bullseyeMergeTbl[a1..b1] .. bullseyeMergeTbl[ax .. bx]
   else
      res = ""
   end
   rawset(self, s, res)
   return res
end

setmetatable(bullseyeMergeTbl, _BullseyeMergeTbl)

Cov.bullseyeMergeTbl = bullseyeMergeTbl -- for unit testing


-- Merge coverage data for a file
--   events :  <line_num>  ->  <eventString>
--
function Cov:mergeBullseye(filename, events)
   local mevents = self:getFileTable(filename,"bdat")
   for lnum,str in pairs(events) do
      local mstr = mevents[lnum] or ""
      if str == "" then
         str = mstr
      elseif mstr ~= "" then
         -- Here we could assert that #mstr == #str ...
         str = bullseyeMergeTbl[mstr .. "_" .. str]
      end
      mevents[lnum] = str
   end
end


local beEventEncodingTbl = {
   _function    = "o",
   _decision    = "N",
   _condition   = "n",
   tf_condition = "y",
   TF_decision  = "Y",
   X_function   = "x",
   ["X_switch-label"] = "S",
   ["_switch-label"] = "s"
}

function Cov:loadBullseye(text)
   local btbl = {}                          -- <filename> -> <bdat_structure>

   local rows = csv.decode("#csv "..text)
   for n,r in ipairs(rows) do
      local src, kind, event, lnum = r.Source, r.Kind, r.Event, tonumber(r.Line)

      -- If one of the fields is nil, report error
      if not (src and lnum and r.Letter and kind and event and r.Function) then
         return nil, "Error while parsing Bullseye generated CSV file at line "..(n+1)
      end

      -- Find/create bdat for this line's source file
      local bdat = btbl[src]
      if not bdat then
         bdat = {}
         btbl[src] = bdat
      end

      -- Convert Bullseye symbols to internal format
      event = beEventEncodingTbl[event.."_"..kind] or event

      -- Add data into bdat
      if bdat[lnum] then
         bdat[lnum] = bdat[lnum] .. event
      else
         bdat[lnum] = event
      end
   end

   for src, events in pairs(btbl) do
      -- fill in empty slots in events table
      for n = 1, maxn(events) do
         if not events[n] then events[n] = "" end
      end
      self:mergeBullseye(src, events)
   end

   return true
end


----------------------------------------------------------------------------
-- gcov Coverage Files
----------------------------------------------------------------------------

-- Merge coverage data from a .gcov file (output of GCOV)
--
function Cov:loadGcov(text)
   local tbl = util.stringSplit(text, "\n")
   local dat

   for _,line in ipairs(tbl) do
      local execCount, lnum, rest = line:match(" *(.-): *(.-):(.*)")

      local n = tonumber(lnum)
      if n == 0 then
         local srcName = rest:match("Source:(.*)")
         if srcName then
            dat = self:getFileTable(srcName, "dat")
         end
      else
         if execCount == "#####" then
            execCount = 0
         else
            execCount = tonumber(execCount)
         end
         if execCount and n then
            dat[n] = (dat[n] or 0) + execCount
         end
      end
   end

   return dat ~= nil, ""
end


----------------------------------------------------------------------------
-- Native (CSV) Coverage Files
----------------------------------------------------------------------------

-- The native format supports both input and output (support for other
-- formats is generally read-only).
--
-- Two types of coverage data are supported:
--
--  1. LCT, or line counts.  Each each line of code is marked either executable
--     or not, and the number of times it was executed.  This is generated by
--     gcov and DevPartner.
--
--  2. BEC, or Bullseye coverage.  Each line of code is marked with an array
--     of events that describes functions, conditions, decisions, and
--     whether or not they have been covered. This is supported by Bullseye,
--     and the internal format is intended to directly represent Bullseye
--     data.
--
-- CSV files store one row per source file.  Field names include:
--
--  file : file name
--
--  lct  : encoding of all LCT information for the file.
--
--         This is a sequence of colon-delimited substrings, one per line of
--         source.  If a line of source is not executable, then its
--         substring is empty; otherwise, it holds the number (decimal) of
--         times the line was executed.
--
--  bec  : encoding of all BEC information for the file.
--
--         This is a sequence of colon-delimited substrings, one per line of
--         source.  Each substring holds the array of event codes (possibly
--         empty) for the line.
--


-- Merge coverage data from our native CSV format.  CSV file must have
-- 'file' and either 'lct' or 'bec' fields.
--
function Cov:loadCSV(text)
   local tbl, err
   tbl, err = csv.decode(text)
   if not tbl then return tbl, err end

   if tbl[1] and not (tbl[1].file and (tbl[1].lct or tbl[1].bec)) then
      return nil, "Bad LCT/BEC file: missing file or lct/bec field"
   end

   -- Merge coverage data from tbl.
   --   tbl[1..n] -> row
   --   row.file  -> filename
   --   row.lct   -> line counts string
   --   row.bec   -> line event string

   for _,row in ipairs(tbl) do
      -- Merge LCT data
      if row.file and row.lct and row.lct ~= "" then
         local dat = self:getFileTable(row.file,"dat")
         local n = 1
         for lcnt in row.lct:gmatch("([^%:]*)%:?") do
            if lcnt ~= "" then
               dat[n] = (dat[n] or 0) + tonumber(lcnt)
            end
            n = n + 1
         end
      end

      -- Merge BEC data
      if row.file and row.bec and row.bec ~= "" then
         self:mergeBullseye(row.file, util.stringSplit(row.bec, ":"))
      end
   end

   return true
end


-- Merge coverage data from a file in DPXML/CSV/Bullseye/gcov format
--
-- On success, returns:  true
-- On failure, returns:  nil, <message>
--
-- Note: loadFile was split into loadFile and loadText to facilitate testing in cov_q.lua
--
function Cov:loadFile(fname)
   local file, err = io.open(fname)
   if not file then
      return file, err
   end

   local text = file:read("*a")
   file:close()
   return self:loadText(text)
end


function Cov:loadText(text)
   if text:find("^#") then
      return self:loadCSV(text)
   elseif text:find("%-: *0:Source:") then
      return self:loadGcov(text)
   elseif text:find('"Source","Line","Letter","Kind","Event","Function"') then
      return self:loadBullseye(text)
   else
      return self:loadDPXML(text)
   end
end


local function countChars (str, chars)
   local str, count = string.gsub(str, chars, "%0")
   return count
end


-- Compute fields derived from bdat;  bdat is the result of the Bullseye merges.
--
function Cov:deriveBECFields(row)
   row.bec = table.concat(row.bdat, ":")

   row.functTotal = countChars(row.bec, "[xo]")
   row.functCov   = countChars(row.bec, "x")

   -- Decisions/conditions count as 2 possible outcomes; switch counts as 1
   row.condTotal  = ( countChars(row.bec, "[ntfyNTFY]")*2
                      + countChars(row.bec, "[sS]") )
   row.condCov    = ( countChars(row.bec, "[tfTFS]")
                      + countChars(row.bec, "[yY]")*2 )
end


-- Compute fields derived from dat;  dat is the result of the merges.
--
function Cov:deriveLCTFields(row)
   -- scan dat[]
   local dat = row.dat
   local nZero, nExec = 0, 0  -- nZero + nExec = executable lines
   for n,v in pairs(dat) do
      if v == 0 then
         nZero = nZero + 1
      else
         nExec = nExec + 1
      end
   end

   local nTotal = nExec + nZero

   row.linesExecuted    = nExec
   row.linesNotExecuted = nZero
   row.linesExecutable  = nTotal
   row.pctExecuted      = nTotal==0 and 100 or (100 * nExec / nTotal)

   -- Construct line counts string
   local t = {}
   for n = 1, maxn(dat) do
      t[n] = dat[n] or ""
   end
   row.lct = table.concat(t, ":")
end


function Cov:deriveFields()
   for _,row in ipairs(self) do
      if row.dat then
         self:deriveLCTFields(row)
      elseif row.bdat then
         self:deriveBECFields(row)
      end
   end
end


-- Write specified columns to a CSV file
--
function Cov:fwrite(f, colNames)
   if not colNames then
      local hasLCT, hasBEC = self:getTypes()
      colNames = string.format("file%s%s%s%s",
         hasLCT and ",linesExecutable,linesExecuted,pctExecuted" or "",
         hasBEC and ",functTotal,functCov,condTotal,condCov" or "",
         hasLCT and ",lct" or "",
         hasBEC and ",bec" or "")
   end
   return csv.writeFile(f, self, colNames)
end


-- This function returns two arguments:
-- The first argument is true if LCT data is present
-- The second argument is true if BEC data is present
--
function Cov:getTypes ()
   local hasLCT, hasBEC
   for k,v in pairs(self) do
      if v.lct then hasLCT = true end
      if v.bec then hasBEC = true end
      if hasLCT and hasBEC then break end
   end
   return hasLCT, hasBEC
end
return Cov
