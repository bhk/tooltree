-- source.lua : Source Objects
--
-- A "source" represents a body of text to be processed by smark.
-- FileSource instances correspond to files, and SubSource instances
-- correspond to sub-documents that appear within a file (for example, a
-- table cell).
--
-- SubSources know about their containing source so locations of syntax
-- errors can be translated back to the original file and line number.
-- FileSources know about the file which referenced them, so when errors are
-- countered Smark can display the chain of events that led to the file
-- being processed.
--
-- To format and display messages for a user, override the PrintError
-- method.  Instances that do not override PrintError will delegate it to
-- the source object from which they were created.
--
-- Usage:
--
-- topSource = require "source"
--
--     This module returns a partially functional source instance that
--     supports only the `newFile` and `warn` methods.
--
-- newSource, err = source:newFile(fileName [, data [, pos]])
--
--     Create new source that reads from a file.
--
--     If `fileName` is relative, it is first treated as relative to the
--     directory of the invoked source's fileName.  If it fails to read a
--     file there, it is then treated as relative to the current working
--     directory.
--
--     If `data` is non-nil, it will be used as the contents of the
--     file (the file contents will not be read from the file system).
--
--     `pos` is the position in `source` of the directive that triggered the
--     file load (for error reporting purposes).  Use nil when the directive
--     is the entirety of `source`, or when `source` is the root source.
--
--     On failure to open or read the file, this returns nil and err, where
--     err is the error message returned from io.open or io.read error.
--
-- source.data
--
--     A string containing all of the text for `source`.
--
-- source.fileName
--
--     The name of the file whose contents are stored in `source.data`.  This
--     is nil for SubSources.
--
-- source:warn(pos, format, ...)
--
--     Display a warning to the user, identifying the location at offset
--     `pos`.  If pos is 0 or nil, the location is associated with the
--     entire source, and not any specific location within it.
--
-- fileSource, pos, line, col = source:where(pos)
--
--     Find the FileSource from which `source` was extracted and the position
--     within that file.  `pos`, `line`, and `col` may be nil if location
--     within file is unknown.
--
-- newSource = source:extract(pos, runs, suffix)
--
--     Create a new source that reads from a subdocument of `source`.  The
--     body of the new source is constructed from byte ranges in `source`
--     described by `runs`:
--
--        runs = {
--           {startPos1, endPos1},
--           {startPos2, endPos2},
--           ...
--        }
--
--     As in string.sub(), start and end positions are inclusive.
--
--     `suffix` is a string to be appended to each run (e.g. "\n").
--
--     `pos` is the offset into `source` of the element that contains this
--     subdocument.  Errors in `source` that are not associated with any
--     position (pos==0 or nil) will be identified with this position in the
--     parent document.


local Object = require "object"
local smarkmisc = require "smarkmisc"
local lfsu = require "lfsu"


--------------------------------
-- Source: Generic methods and properties
--
--   source.parent = source that created this source
--------------------------------

local Source = Object:new()

local FileSource, SubSource, StringSource


-- Delegate display and formatting back up inclusion chain
--
function Source:printError(message, source, pos, line, col)
   if self.parent then
      self.parent:printError(message, source, pos, line, col)
   else
      io.stderr:write("ERROR: Dropped PrintError")
   end
end


function Source:addFile(filename)
   table.insert(self.files, filename)
end


function Source:warn(pos, ...)
   self:printError(string.format(...), self:where(pos))
end


function Source:where(pos)
   if not pos or pos < 1 then
      return self
   end

   return self, pos, smarkmisc.findRowCol(self.data, pos)
end


function Source:newFile(fileName, data, pos)
   if not data then
      -- find & read file
      local dir = lfsu.splitpath(self:where().fileName or "./")
      local paths = { lfsu.resolve(dir, fileName) }
      if fileName ~= paths[1] then
         paths[2] = fileName
      end

      local err
      for _, path in ipairs(paths) do
         data, err = smarkmisc.readFile(path)
         if data then
            fileName = path
            break
         end
      end
      if not data then
         table.insert(paths, 1, "")
         local locs = table.concat(paths, "\n ... attempted to open: ")
         self:warn(pos, "Could not find file: %s%s\n", fileName, locs)
         smarkmisc.fatal("")
      end
      self:addFile(fileName)
   end
   return FileSource:new(self, pos, fileName, data)
end


function Source:newString(pos, str)
   return FileSource:new(self, pos, "(unknown)", str)
end


function Source:extract(pos, runs, suffix)
   return SubSource:new(self, pos, runs, suffix)
end


-- Create new data-less Source that directs warings back to a position in
-- this source.
--
function Source:newWarner(posInParent)
   local parent = self
   local w = {}
   w.data = ""
   function w:warn(pos, ...)
      return parent:warn(pos + posInParent, ...)
   end
   return w
end

------------------------------------------------------------------------
-- FileSource: reads from a file.
--    fileSource.parent = source that included fileSource
------------------------------------------------------------------------

FileSource = Source:new()


function FileSource:initialize(parent, pos, fileName, data)
   -- markup.lua does not deal with tabs or CRs; expanding tabs early
   -- (here) simplifies error reporting.
   self.data = smarkmisc.expandTabs(data:gsub("\r", ""))
   self.fileName = fileName
   self.parent = parent
   self.files = parent.files
   self.parentPos = pos
end


------------------------------------------------------------------------
-- SubSource: a SubSource's 'data' has been extracted from its parent's 'data'.
--
-- Call source:extract() to construct a SubSource.
------------------------------------------------------------------------

SubSource = Source:new()


-- see Source:extract()
function SubSource:initialize(parent, pos, runs, suffix)
   self.parent = parent
   self.files = parent.files
   self.parentPos = pos or runs[1] and runs[1][1]
   self.runs = runs
   self.suffix = suffix or ""

   -- construct data (assume tabs have already been expanded)
   local t = {}
   for _, r in ipairs(runs) do
      assert(r[2] >= r[1] - 1)
      table.insert(t, parent.data:sub(r[1], r[2]) .. self.suffix)
   end
   self.data = table.concat(t)
end


function SubSource:where(pos)
   local parentPos = self.parentPos

   if not pos or pos < 1 then
      pos = 1
   end

   for _, r in ipairs(self.runs) do
      local runLen = r[2] - r[1] + 1 + #self.suffix
      if pos <= runLen then
         parentPos = pos + r[1] - 1
         break
      end
      pos = pos - runLen
   end

   return self.parent:where(parentPos)
end


----------------------------------------------------------------
-- SmarkSource: report errors as appropriate for smark
----------------------------------------------------------------

local SmarkSource = Source:basicNew()


local warnTemplate =
   "smark warning:\n" ..
   "{F}:{L}:{C}: {E}\n" ..
   "{F}: {T}\n" ..
   "{F}: {S}^\n" ..
   "{D}"


function SmarkSource:printError(message, source, pos, line, col)
   local warning
   local fileName = source.fileName
   local data = source.data

   if not fileName then
      warning = "smark error: " .. message
   elseif not line then
      warning = string.format("%s: %s\n", fileName, message)
   else
      local fields = { F = fileName, L = line, C = col }
      -- split message into first line & more verbose description
      fields.E, fields.D = message:match("([^\n]*)\n?(.*)")
      fields.T = data:match("[^\r\n]*", pos-col+1)
      fields.S = (" "):rep(col-1)
      warning = warnTemplate:gsub("{(%w*)}", fields)
   end
   io.stderr:write(warning)

   while source.parent and source.parent.data do
      source, pos, line, col = source.parent:where(source.parentPos)
      fileName = source.fileName or "??"
      message = ("   included from: %s:%s:\n"):format(fileName, line or "??")
      io.stderr:write(message)
   end

   source.didWarn = true
end


function SmarkSource:initialize()
   self.files = {}
end


return SmarkSource:new()

