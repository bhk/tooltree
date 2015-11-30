-- smarkmisc: miscellaneous utility functions

-- Remove trailing spaces and tabs
--
local function rtrim(str)
   -- Avoid str:sub() in already-trimmed case
   if str:match("[ \t\n]", -1) then
      for n = #str-1,1,-1 do
         if str:find("^[^ \t\n]",n) then
            return str:sub(1,n)
         end
      end
      return ""
   end
   return str
end


-- Expand tabs to spaces, assuming tab stops every 8 columns
--
local function expandTabs(str)
   if str:match("\t") then
      local lstart = 1
      local function et(c, pos)
         if c=="\n" then
            lstart = pos
         else
            local exp = 8 - (pos-lstart-1)%8
            lstart = lstart - exp + 1
            return string.rep(" ", exp)
         end
      end
      str = str:gsub("([\n\t])()", et)
   end
   return str
end


-- Given a position within a document, return line and row (both 1-based)
--
local function findRowCol(str, pos)
   local lnum, lpos, lstart = 0, 1, 1
   while lpos and lpos <= pos do
      lnum = lnum + 1
      lstart = lpos
      lpos = str:match("\r?\n()", lpos)
   end
   return lnum, pos - lstart + 1
end


local function urlEncodeByte(c)
   return "%"..string.format("%02x", string.byte(c))
end


local function urlEncode(str)
   return ( str:gsub("[?#;&%% \"<>%[\\%]^`{|}]", urlEncodeByte) )
end


-- urlNormalize: an idempotent function; should not modify valid URLs.
--
local function urlNormalize(str)
   str = str:gsub("[%% \"<>%[\\%]^`{|}]", urlEncodeByte)
   str = str:gsub("%%25(%x%x)", "%%%1")  -- un-encode unnecessarily-encoded '%' chars
   return str
end


local function fatal(fmt, ...)
   local message = fmt and string.format(fmt, ...) or "smark exited."
   error("exit: " .. message)
end


local function readFile(name)
   local f,err = io.open(name, "r")
   if not f then
      return f, err
   end
   local data = f:read("*a")
   f:close()
   return data
end


-- Find index into string corresponding with line number
--
local function lineToPos(str, line)
   local n = 1
   local pos = 1
   for p in str:gmatch("\n()") do
      n = n + 1
      if n > line then break end
      pos = p
   end
   return pos <= #str and pos or #str
end


return {
   rtrim = rtrim,
   expandTabs = expandTabs,
   findRowCol = findRowCol,
   urlEncode = urlEncode,
   urlNormalize = urlNormalize,
   readFile = readFile,
   fatal = fatal,
   lineToPos = lineToPos,
}
