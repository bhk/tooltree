-- tree.lua
--
-- Errors generated:
--   tree: unbalanced parens in pattern <pattern>
--   tree: cannot open directory <dir>
--   cannot open <dir>: Permission denied
--
-- todo:
--   @include

local xpfs = require "xpfs"
local lfsu = require "lfsu"

require "lua52"

-- Factor out the case of the drive letter in Windows
local function abspath(name)
   return ( lfsu.abspath(name):gsub("^[A-Z]", string.lower) )
end

local function rtrim(str)
   return str:match("^(.-) *$")
end

local function dirPlusFile(dir, file)
   if dir:sub(-1,-1)~="/" then
      dir = dir .. "/"
   end
   return file and dir..file or dir
end

-- Functional combinators

local function andF(f,g) return function(x) return f(x) and g(x) end end
local function orF(f,g)  return function(x) return f(x) or g(x) end end
local function notF(f)   return function(x) return not f(x) end end
local function trueF()   return true end
local function falseF()  return false end


----------------------------------------------------------------
-- Treespec Patterns
----------------------------------------------------------------
--
-- Treespec patterns resemble Perforce client spec patterns.
--
-- Patterns are matched against file names to determine whether a file
-- belongs to the set.  Comparisons are based solely on the contents of the
-- file name strings (not on file system state), so these function will
-- handle imaginary paths.
--
-- From patterns we construct functions to test directory names to determine
-- whether we need to descend into a directory.  Given a pattern we can put
-- a directory into one of three categories:
--
--   ALL files are matched.  To be precise, this means that all files that
--     could potentially exist as descendants of the directory will
--     necessarily match the pattern.  For example, everything under
--     directory "a" is matched by the pattern "a/...".
--
--   NONE of its files could be matched by the pattern.  For example, no files
--     under "a" could be matched by "b/..." (or by "a", for that matter.)
--
--   MAYBE some of its files are matched.  In other words, the pattern covers
--     a subset of the namespace under the directory, so we cannot conclude
--     whether all files are matched or avoided.  For example, "a/b" may or
--     may not match files under "a".
--
-- We can define category ANY = directories in MAYBE or ALL.
--
-- Depending on the type of treespec clause, we may be interested in
-- different categories.
--
--    <pat>  : NONE vs. ALL/MAYBE (ANY)
--    -<pat> : ALL  vs. NONE/MAYBE (notall)
--    &<pat> : NONE vs. ALL/MAYBE (ANY)
--


-- Construct array of lpats (Lua patterns).  Strings that match one or more
-- tpats will match one or more tpats (treespec patterns).
--
local function tpatsToLpats(tpats)
   local lpats = {}

   for _,pat in ipairs(tpats) do
      -- construct a Lua pattern from a Treespec pattern (except for "()")

      pat = pat:gsub("[%^%$%%%+%-%.]", "%%%1")
      pat = pat:gsub("*", "[^/]*")
      pat = pat:gsub("%%%.%%%.%%%.", ".*")
      pat = pat:gsub("%?", ".?")
      pat = "^"..pat.."$"

      table.insert(lpats, pat)
   end

   -- Convert (x|y|...) alternatives to a set of complete patterns
   --   Possible optimization:  (c|h|foo) => ([ch]|foo)

   local n = 1
   while lpats[n] do
      local p = lpats[n]
      local pre,pexp,post = p:match("(.-)(%b())(.*)")
      if pre then
         table.remove(lpats, n)
         for a in pexp:gmatch("%(?([^|%)]*)[|%)]") do
            table.insert(lpats, pre..a..post)
         end
      else
         if p:match("[%(%)]") then
            error("tree: unbalanced parens in pattern " .. tpat)
         end
         n = n + 1
      end
   end

   return lpats
end

local function matchTpats(tpats)
   local lpats = tpatsToLpats(tpats)
   local expr = "false"

   for _,pat in ipairs(lpats) do
      expr = string.format("%s or f:match(%q)", expr, pat)
   end
   expr = expr:gsub("^false or ","")

   -- Use "not not <e>" instead of "<e> and true or false" to avoid bug
   local chunk = "return function (f) return not not ("..expr..") end"
   return load(chunk)()
end

-- Return a function that tests a file, given a treespec pattern
--
--   f(file) returns TRUE when the pattern matches the file
--
local function matchFile(tpat)
   return matchTpats( {tpat} )
end


-- Return function that tests a directory for category ALL
--
--   f(dir) returns TRUE when the pattern matches ALL under dir
--
-- If the pattern does not end in "..." then NO directory will be ALL
-- matched.  Patterns that end in "..." and match "dir/" will match ALL
-- under "dir".
--
--
local function matchDirAll(tpat)
   local trail = tpat:match("%.+$")
   if trail and #trail % 3 == 0 then
      local ftest = matchFile(tpat)
      return function(d) return ftest(d.."/") end
   else
      return falseF
   end
end

-- Construct an array of patterns that represent posssible parent
-- directories of files matching a pattern.  We do not need to look
-- past any "..." or past the last "/" in the string.
--
--   file pattern -> dir patterns (dirs in 'ANY')
--           /a/b    /  /a
--           /a/*    /  /a
--         /a/...    /  /a  /a/...
--       /a/x*y/c    /  /a  /a/x*y
--      /...x/y/z    /...
--           c:/a    c:/
--       c:/a/b/c    c:/  c:/a  c:/a/b
--
-- Relative paths would complicate it a bit ("a/b" -> ".", "a") and require
-- distinguishing "c:" the drive from "c:" the relative directory.
--
local function dirAnyPatterns(tpat)
   local t = {}
   local pat = tpat:match("^(.-%.%.%.)") or tpat:match("^(.*/)") or ""
   local dir,s = pat:match("([^/]*)(/?)")
   t[1] = dir..s
   for e in pat:gmatch("/[^/]*")  do
      dir = dir .. e
      if e ~= "/" then
         table.insert(t, dir)
      end
   end
   return t
end


-- Return function that tests a directory for category ANY
--
--   f(dir) returns TRUE when the pattern matches ANY files under dir
--
local function matchDirAny(tpat)
   return matchTpats( dirAnyPatterns(tpat) )
end


----------------------------------------------------------------
-- Treespec File Handling
----------------------------------------------------------------

-- return true if directory a is an ancestor of b or equal to b
local function covers(a,b)
   return a == b or #a < #b and a == b:sub(1,#a) and b:sub(#a+1,#a+1) == "/"
end

-- Return table describing the treespec.
--   .ftest = file predicate
--   .dtest  = directory match predicate
--   .roots = array of root directories from which to descend
-- On entry:
--    spec = contents of treespec file
--    top = top directory
--
local function parseSpec(spec, top, name)
   local ftest = falseF
   local dtest = falseF
   local roots = {}

   local function expandRoots(pat)
      -- ignore everything after first non-literal character
      local pre = pat:match("^[^%?%(%[%*%.]*"):match("^(.-)/[^/]*$")
      if not pre then
         error("tree: bad absolute path: "..pat)
      end

      local n = 1
      while roots[n] do
         if covers(roots[n], pre) then
            return
         elseif covers(pre, roots[n]) then
            table.remove(roots,n)
         else
            n = n + 1
         end
      end
      roots[n] = pre
   end

   -- Specs can contain abs and rel paths and "..", so we need abspath of
   -- top in order to match patterns accurately.
   top = top and abspath(top) or "/"
   top = dirPlusFile(top)

   for ln in spec:gmatch("([^\r\n]+)\r?\n?") do
      local typ,patsp = ln:match("^%s*([%-&]?)([^#]*)")
      local pat = patsp and rtrim(patsp) or ""
      pat = lfsu.resolve(top, pat)

      if typ == "-" then
         ftest = andF( notF(matchFile(pat)), ftest)
         dtest = andF( notF(matchDirAll(pat)), dtest)
      elseif typ == "&" then
         ftest = andF( matchFile(pat), ftest)
         dtest = andF( matchDirAny(pat), dtest)
      else
         expandRoots(pat)
         ftest = orF( matchFile(pat), ftest)
         dtest = orF( matchDirAny(pat), dtest)
      end
   end

   for n,r in ipairs(roots) do
      if not r:match("/") then
         roots[n] = roots[n] .. "/"
      end
   end
   table.sort(roots)

   return {
      ftest = ftest,
      dtest = dtest,
      roots = roots,
      top = top,
      name = name
   }
end

----------------------------------------------------------------
-- File Operations
----------------------------------------------------------------

-- Traverse file system trees, returning files as an array of tables:
--    file.name = file name
--    file.perm = permissions string (e.g. "drwxr--r--")
--
-- On entry:
--   dirs       : starting directories; roots of tree to traverse
--   spec.ftest : function to test files for inclusion in the set.
--           When ftest(filepath) returns false, the file is excluded.
--   spec.dtest : function to test directories for inclusion.  When
--           dtest(dirpath) returns false, the directory is skipped
--           (the traversal is pruned).
--
local function findx(dirs, spec)
   local ftest = spec.ftest or trueF
   local dtest = spec.dtest or trueF
   local dirsVisited = {}

   local function tfind(t, dir)
      if not dtest(dir) then
         return
      end
      table.insert(dirsVisited, dir)

      local entries = assert(xpfs.dir(dir), "tree: cannot open directory: " .. dir)
      for _, i in ipairs(entries) do
	 local name = dirPlusFile(dir, i)
         local st = xpfs.stat(name, "kp")
         if not st then
            -- do nothing
         elseif st.kind == "f" then
            if ftest(name) then
               table.insert(t, {name = name, perm = "-" .. st.perm} )
            end
	 elseif st.kind == "d" and i ~= "." and i ~= ".." then
	    tfind(t, name)
	 end
      end
   end

   local t = {}
   for _,d in ipairs(dirs) do
      local st = xpfs.stat(d, "k")
      -- should do this check inside tfind as part of error handling
      if not st or st.kind ~= "d" then
         error("tree: cannot open directory: " .. d)
      end
      tfind(t, abspath(d))
   end
   return t, dirsVisited
end


-- Find files under 'dir', restricting to those that match the treespec
--
-- find() looks for a treespec in the specified directory and if not found
-- in its parent directory, and so on until one is found or top-most parent
-- is reached.
--
--   dir      : "top" directory
--   specName : file name to use in looking for treespec
--              nil/false => skip treepsec, return all files
--   external : true => include files outside of 'dir' when the
--                 treepsec refers to them.
--              false/nil => restrict search to descendants of dir
--
local function find(dir, specName, external)
   local spec = { ftest = trueF, dtest = trueF }
   dir = abspath(dir)

   if specName then
      local specDir, prev = dir
      repeat
         local name = dirPlusFile(specDir, specName)
         local specstr = lfsu.read(name)
         if specstr then
            spec = parseSpec(specstr, specDir, name)
            break
         end
         prev, specDir = specDir, (lfsu.splitpath(specDir))
      until specDir == prev
   end

   local roots = external and spec.roots or {dir}
   local f, d = findx(roots, spec)
   return f, d, spec
end


local tree = {
   -- expose for testing
   _ = {
      rtrim = rtrim,
      dirAnyPatterns = dirAnyPatterns,
      covers = covers
   },

   matchFile = matchFile,
   matchDirAll = matchDirAll,
   matchDirAny = matchDirAny,

   parseSpec = parseSpec,
   findx = findx,
   find = find
}

return tree
