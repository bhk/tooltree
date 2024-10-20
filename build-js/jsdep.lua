local qtest = require "qtest"
local scanjs = require "scanjs"
local getopts = require "getopts"
local fsu = require "fsu"

local isWin = false -- todo: require "iswin"
local fu = isWin and fsu.win or fsu.nix


local jsPath = os.getenv("NODE_PATH") or ""

local usageStr = [[
Usage:  jsdep [OPTIONS] JSFILE

   Find all JavaScript files required by JSFILE by parsing the sources to
   detect calls to the Node/CommonJS `require` function.  Output all
   file names separated by a space.

Options:
   -o OUTFILE   : write output to OUTFILE.
   --bundle     : output a bundle JavaScript file (instead of dependencies)
                  including the input file and all its dependencies.
   --html       : output HTML including the bundled JavaScript.
   -MF MKFILE   : write Make dependency rules to MKFILE.  The target for
                  the rules is given by -MT, if present, or -o otherwise.
   -MT TARGET   : specify the target name for rules generated by -MF.
   -MTF         : declare MKFILE itself as a target for non-oo rules.
   -Moo PATTERN : add order-only dependencues (when -MF is given),
                  computed by expanding PATTERN for each dependency.
   --path=PATH  : provide search path for JavaScript files; overrides
                  the NODE_PATH environment variable.

Environment variables:
   NODE_PATH: a colon-delimited list of directories to be searched.

Notes:
   Within PATTERN the following names are expanded:

     ^F = the dependency
     ^B = the basename (non-suffix portion) of the dependency
     ^S = the suffix of the dependency (e.g. ".js")

   When -MOO is specified, after PATTERN is applied, if the resulting name
   matches that of the target, it will be omitted.
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


local function computeOOs(files, pattern, target)
   local oos = newArray()
   for ndx, file in ipairs(files) do
      local suffix = file:match("%.[^%./]*$") or ""
      local basename = file:match("(.*)%.[^%./]*$") or file
      local name = pattern:gsub("%^F", file)
        :gsub("%^B", basename)
        :gsub("%^S", suffix)
      if name ~= target then
         oos:insert(name)
      end
   end
   return oos
end

----------------------------------------------------------------
-- main
----------------------------------------------------------------


local options = "--path= -o= --bundle --html -MF= -MT= -MTF -Moo="
local words, opts = getopts.read(arg, options)

if opts.path then
   jsPath = opts.path
end

if not opts.o and not opts.MF then
   return fail("neither `-o FILE` nor `-MF FILE` specified.")
end

if #words ~= 1 then
   return fail("invalid arguments\n\n%s", usageStr)
end
local filename = fu.cleanpath(words[1])

-- scan dependencies, populating files[]

local properties = scanFile(filename)

if opts.o then
   local fo = openFile(opts.o)

   local out
   if opts.bundle then
      out = makeBundle()
   elseif opts.html then
      out = makeHTML(filename, properties)
   else
      out = makeDeps()
   end

   fo:write(out)
   fo:close()
end

-- MF <file>

if opts.MF then
   local target = opts.MT or opts.o or
      fail("-MF given, but no -MT or -o to provide target name")
   local fo = openFile(opts.MF)

   local out = ""
   if opts.MTF then
      out = opts.MF .. ": " .. files:concat(" ") .. "\n"
   end

   out = out .. target .. ": " .. files:concat(" ")

   local oos = newArray()
   if opts.Moo then
      oos = computeOOs(files, opts.Moo, target)
      out = out .. " | " .. oos:concat(" ")
   end
   out = out .. "\n" .. files:concat(":\n") .. ":\n"
   out = out .. oos:concat(":\n") .. ":\n"
   fo:write(out)
   fo:close()
end


return 0
