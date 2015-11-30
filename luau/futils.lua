----------------------------------------------------------------
-- futils.lua
--
-- DEPRECATED:  use "fsu" or "lfsu" instead.
--
-- Use futils.new() to construct a table including OS- or CWD-dependent
-- functions and values:
--
--   relpath(path)      Relative path
--   abspath(path)      Absolute path
--   resolve(dir,path)  Combine base path and absolute/relative path
--   eqForm(path)       Get canonical form (string eq => equivalence)
--   prettify(path)     Return uniform presentation; case preserving
--   curdir             Current working directory at time of new()
--   winDrive           DOS/Windows drive letter (nil => non-Windows)
--
-- new() can be passed a current working directory path, or nil to get it
-- from xpfs.getcwd().  Otherwise, there is no dependency on xpfs.
--
-- When directory names are returned they are in a form that can be passed
-- to XPFS functions, so they do NOT include a trailing slash except in the
-- case of a root directory ("/" on UNIX, "<slash>" or "<drive>:<slash>" on
-- Windows).
--
-- Todo:
--  * eqForm() ignore care on OSX (all case-insensitive FS's?)
--  * Always require xpfs; always check OS on load
--  * Win vs. NIX is messy; higher-level functions are independent of OS, but
--    have dependency on "current OS"... either OO style or purer functional
--    style (no dynamically created closures) would be better.
--  * In Window,  functions should return normalized "\" form, since this
--    is needed in some contexts, while accepting either "/" or "\".
----------------------------------------------------------------
local fsu = require "fsu"

local futils = {}

local function ident(x) return x end

--------------------------------
-- nix-only
--------------------------------

futils.nixComputeRelPath = fsu.nix.relpathto
futils.nixSplitPath = fsu.nix.splitpath
futils.nixResolve = fsu.nix.resolve

--------------------------------
-- win-only
--------------------------------

futils.winComputeRelPath = fsu.win.relpathto
futils.winResolve = fsu.win.resolve

-- consistent presentation
--
function futils.winPrettify(path)
   path = path:gsub("\\", "/")
   return ( path:gsub("^[A-Z]:/", string.lower) )
end

-- construct form that compares with all equivalent paths
--
function futils.winEqForm(path)
   return path:gsub("\\", "/"):lower()
end

-- Split "dir/name" into "dir" and "name".  Root dir = "/" or "[letter]:/"
--
function futils.winSplitPath(path)
   local a,sl,b = path:match("^(.*)([/\\])([^/\\]*)$")
   if not a then
      return ".", path
   elseif a == "" or a:match("^[A-Za-z]%:$") then
      return a..sl, b
   end
   return a, b
end

--------------------------------
-- common
--------------------------------

futils.cleanPath = fsu.nix.cleanpath
futils.read = fsu.nix.read
futils.write = fsu.nix.write

-- Return parent directory of path (assumes path does not end in redundant "/")
--
function futils.parent(path)
   return path:match("^(.-/.*)/[^/]*$") or path:match("^(.*/)[^/]*$") or path
end

function futils.removeTree(name)
   local lfsu = require "lfsu"
   return lfsu.rm_rf(name)
end

function futils.makeParentDir(path)
   local lfsu = require "lfsu"
   local parent = lfsu.splitpath(path)
   return lfsu.mkdir_p(parent)
end

futils.__index = futils


-- If nil is passed for curdir, xpfs will be used.
--
function futils.new(curdir)
   if not curdir then
      local xpfs = require "xpfs"
      curdir = xpfs.getcwd()
   end

   -- Initialize first with platform-independent functions
   local me = {
      curdir    = curdir,
      winDrive  = curdir:match("^(%a:)"),
      resolve   = futils.nixResolve,
      splitPath = futils.nixSplitPath,
      computeRelPath = futils.nixComputeRelPath,
      eqForm    = ident,
      prettify  = ident,
      abspath   = false,
      relpath   = false,
   }
   setmetatable(me, futils)

   if me.winDrive then
      me.prettify  = futils.winPrettify
      me.eqForm    = futils.winEqForm
      me.resolve   = futils.winResolve
      me.splitPath = futils.winSplitPath
      me.computeRelPath = futils.winComputeRelPath
   end

   -- Note: abspath() and relpath() use the current directory this futils
   -- instance was initialized with, which may differ from the actual
   -- current directory if chdir() is called.

   local resolve = me.resolve
   function me.abspath(path)
      return resolve(curdir, path)
   end

   -- relpath() : a cheesy "get relative path" function. This will return an
   -- absolute path unless the relative path is very simple.
   --
   --    dotslash==true => include "./" at front of relative paths.
   --
   local curbase = me.eqForm(curdir):gsub("[^/]$", "%1/")
   function me.relpath(path, dotslash)
      local pre = path:sub(1,#curbase)
      if pre == curbase or me.eqForm(pre) == curbase then
         local rel = path:sub(#curbase+1)
         return (dotslash and "./"..rel or rel)
      end
      return path
   end

   return me
end


return futils
