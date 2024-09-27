local qtest = require "qtest"
local scanjs = require "scanjs"
local getopts = require "getopts"
local fsu = require "fsu"

local isWin = false -- todo: require "iswin"
local fu = isWin and fsu.win or fsu.nix


local jsPath = os.getenv("NODE_PATH") or ""

local usageStr = [[
Usage:

   jsdep [OPTIONS] JSFILE

   Find all JavaScript files required by JSFILE by parsing the sources to
   detect calls to the Node/CommonJS `require` function.  Output all
   file names separated by a space.

   Jsdep may also be used to create a "bundled" JavaScript script.  This
   bundled script includes an implementation of `require` that obtains
   modules from within the bundle itself, without file or network access.
   Otherwise, the behavior of the bundled file should be the same as running
   JSFILE.

Environment variables:

   NODE_PATH: a colon-delimited list of directories to be searched.

Options:

   -o OUTFILE : name the dependency file to output (not optional).

   -odep DEPFILE : name of a dependency file to generate.  This will
       contain GNU Make dependency rules for OUTFILE listing.

   --path=PATH : provide search path for JavaScript files; overrides
       the NODE_PATH environment variable.

   --format=FMT : output FMT after replacing each occurrence of `%s`
       with the data that would have been output.

   --bundle : output the bundled JavaScript file.

   --html : output HTML that executes the bundled JavaScript.

]]

local function fail(...)
   print("jsdep: error: " .. string.format(...))
   os.exit(1)
end

local function newArray()
   return setmetatable({}, { __index = table })
end


local function fileExists(name)
   local f = io.open(name, "r")
   if f then
      f:close()
      return name
   end
end


local function readFile(name)
   local f = io.open(name, "r")
   if f then
      local data = f:read("*a")
      f:close()
      return data
   end
end


local function findJSModule(mod, fromFile)
   mod = fu.cleanpath(mod)

   -- If file is absolute or begins with "../" or "./", then ignore
   -- the search path.
   if mod:match("^%.?%.?/") or mod:match("^%a:/$") then
      local fromDir = fu.splitpath(fromFile)
      return fu.resolve(fromDir, mod)
   end

   for dir in jsPath:gmatch("[^:]+") do
      local file = fu.resolve(dir, mod)
      if fileExists(file) then
         return file
      end
   end
   return nil
end


local files = newArray()
local filesIndex = {}   --  filepath --> true/nil
local pathToMod = {}


local function scanFile(file)
   if filesIndex[file] then
      return
   end

   files:insert(file)
   filesIndex[file] = #files

   local src = fsu.nix.read(file)
   if not src then
      return fail("could not read file: %s", file)
   end

   local o = scanjs.scan(src)

   for _, mod in pairs(o.requires) do

      if mod:match("^%a%w*$") then
         -- ignoring "core" module
      else
         local requiredFile = findJSModule(mod, file)
         if not requiredFile then
            return fail("could not find module '%s'\n   required from: %s", mod, file)
         end

         local modPre = pathToMod[requiredFile]
         if modPre then
            -- In order to support different module names, we will need
            -- to re-write source files, replacing the require argument.
            assert(modPre == mod,
                   "Source file referenced via two different module names: "
                      .. modPre .. " and " .. mod)
         else
            pathToMod[requiredFile] = mod
         end
         scanFile(requiredFile)
      end
   end

   return o
end


local function makeDeps()
   return files:concat(" ") .. "\n"
end


local function jsLiteral(str)
   return "'" .. str .. "'"
end

local bundleTemplate = [==[
(function (mods) {
   var loaded = [];
   function require(mod) {
      var m = loaded[mod];
      if (!m) {
         loaded[mod] = m = { exports:{} };
         mods[mod](require, m, m.exports);
      }
      return m.exports;
   }
   require({main});
}({
{mods}
}));
]==]


local function makeBundle()
   local o = newArray()
   for _, path in ipairs(files) do
      local modName = pathToMod[path] or "(main)"
      o:insert( jsLiteral(modName) .. ": " ..
                   "function (require, module, exports) {\n" ..
                   readFile(path) ..
                   "\n}")
   end

   local values = {}
   values.main = "'(main)'"
   values.mods = o:concat(",\n\n")

   return ( bundleTemplate:gsub("{(%a+)}", values) )
end


local htmlTemplate = [[
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>{title}</title>
  </head>
  <body>
    <script charset="utf-8">
{script}
    </script>
  </body>
</html>
]]


local function makeHTML(name, properties)
   local values = {}
   values.script = makeBundle():gsub("</", "<\\/")
   values.title = properties.title or name

   return ( htmlTemplate:gsub("{(%a+)}", values) )
end


local function openFile(filename)
   local fo = io.open(filename, "w")
   if not fo then
      return fail("could not open output file: %s", filename)
   end
   return fo
end


----------------------------------------------------------------
-- main
----------------------------------------------------------------

local options = "--path= -o= --format= --bundle --html --odep="
local words, opts = getopts.read(arg, options)

if opts.path then
   jsPath = opts.path
end

if not opts.o then
   return fail("`-o FILE` not specified.")
end

if #words ~= 1 then
   return fail("invalid arguments\n\n%s", usageStr)
end
local filename = fu.cleanpath(words[1])

-- scan dependencies, populating files[]

local properties = scanFile(filename)

local fo = openFile(opts.o)

local data
if opts.bundle then
   data = makeBundle()
elseif opts.html then
   data = makeHTML(filename, properties)
else
   data = makeDeps()
end

if opts.format then
   data = opts.format:format(data)
end

fo:write(data)
fo:close()

-- odep

if opts.odep then
   local fo = openFile(opts.odep)
   local data = opts.o .. ": " .. files:concat(" ") .. "\n"
   data = data .. files:concat(":\n") .. ":\n"
   fo:write(data)
   fo:close()
end



return 0
