-- requirefile
--
-- `requirefile` loads files from a location relative to a Lua module.
--
-- `requirefile(location) -> data`
-- ---------------------------
--
-- `location` describes the location of the file, in the format
-- `module/rel_path`.  `module` is the name of a Lua module (as passed to
-- `require`) and `rel_path` is the path to the file, relative to the directory
-- containing the Lua module's source file.
--
-- The Lua module's is found by searching `package.path` in the same way
-- that `require` does.
--
-- Example:
--
--    local src = requirefile "foo/a/b.txt"
--
-- If the module `foo` is found in `../utils/foo.lua`, then the file
-- `../utils/a/b.txt` will be read into memory and returned.
--
-- Additionally, if the variable REQUIREFILE_PATH is set, it contains a
-- semicolon-delimited list of paths (empty strings are ignored) that will
-- be prepended to the `rel_path` part of the location.  The first such path
-- that names an file that exists will be used.

local requirePath = os.getenv("REQUIREFILE_PATH") or "."


local function fileExists(name)
   local f = io.open(name, "r")
   if f then
      f:close()
      return name
   end
end


local function searchLuaPath(path, name)
   local repl = name:gsub("%.", "/")
   for p in path:gmatch("[^;]+") do
      local filename = p:gsub("%?", repl)
      if fileExists(filename) then
         return filename
      end
   end
end


local function dir(filename)
   return filename:match("(.*/)") or "./"
end


local function readFile(name)
   local f = io.open(name, "r")
   if f then
      local data = f:read("*a")
      f:close()
      return data
   end
end


local function isSlash(ch)
   return ch == '/' or ch == '\\'
end


local function join(a, b)
   if isSlash(b:sub(1,1)) then
      return b
   end
   local file = a .. (isSlash(a:sub(-1)) and "" or "/") .. b
   file = file:gsub("/%./", "/")
   return file
end


local function requirefile(path)
   local mod, rel = string.match(path, "([^/]+)/(.*)")
   if not mod then
      error("requirefile: module name not given in '" .. path .. "'", 2)
   end

   local modFile = searchLuaPath(package.path, mod)
   if not modFile then
      error("requirefile: module '" .. mod .. "' not found", 2)
   end

   local modDir = dir(modFile)
   for pathDir in requirePath:gmatch("([^;]+)") do
      local file = join( join(modDir, pathDir), rel)
      local data = readFile(file)
      if data then
         return data
      end
   end

   return nil
end


return requirefile
