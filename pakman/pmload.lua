-- pmload: Supports compiling user-supplied chunks of Lua in Pakman.
--
-- 1. Chunks shall be able to call require/loadfile/readfile with relative
--    URIs that are treated as relative to the base URI of the chunk itself.
--    'require' will *not* search LUA_PATH for files.
--
-- 2. The "global" table used by Pakman internally shall be protected from
--    user-provided chunks (package files, files loaded by packages files,
--    and so on).  User-provided chunks shall have their environment table
--    set to a "user global" table, except for package files themselves, who
--    will have the package object set as their environment (whose metatable
--    delegates to the user global table).
--
-- In order to handle relative URIs we need to know the base URI.  Each
-- compiled chunk may have a different base URI, so for each compiled chunk
-- we construct a new instance of each of these functions (require, etc.).
-- These functions are made available to the chunk as locals (upvalues), not
-- globals.  Pedantically speaking, when one of these functions is passed a
-- relative URI, it will be treated as relative to the base URI of the chunk
-- that was granted to the reference to the function.
--

local pml = {}

pml.userGlobals = {}

pml.loaded = {}

-- loadstring with lexically scoped variables (pre-defined upvalues)
--
--  str : same as in loadstring() (chunk to be compiled)
--  name : same as in loadstring()
--  locals : variables to manifest as locals in the compiled chunk
--  globals : table to be set as the environment for the function
--
local function loadstringwith(str, name, locals, globals)
   assert(type(str) == "string")
   local f, err
   if not locals or next(locals) == nil then
      f, err = load(str, name, nil, globals)
   else
      local names, values = {}, {}
      for k,v in pairs(locals) do
         table.insert(names, k)
         table.insert(values, v)
      end
      local c = string.format("local %s=... return function () %s\nend",
                              table.concat(names, ","), str)
      f, err = load(c, name or str, nil, globals)
      if f then
         f = f(table.unpack(values))
      end
   end
   return f, err
end


-- pmfuncs: Return a table of functions that involve compiling code,
-- resolving URIs or retrieving files based on URIs, or both.  Functions
-- provided are: require, dofile, loadfile, loadstring, readfile, resolve
--
-- When a chunk is compiled using these functions, its access to globals is
-- restricted to a specified "user globals" table.  The compiled code is
-- provided with a set of local variables consisting of the functions
-- returned by pmfucs, so the compiled code can in turn compile more code
-- that is similiarly "sandboxed" (not sharing the global table) and aware
-- of its base URI.
--
local function pmfuncs(baseURI, resolveURI, readURI, loaded, userGlobals)
   local t = {}
   userGlobals = userGlobals or pml.userGlobals
   loaded = loaded or pml.loaded

   -- resolve(uri) : return absolute, canonical URI
   function t.resolve(uri)
      return resolveURI(uri, baseURI)
   end

   -- readfile() : return contents of file as string (or nil, errorString)
   function t.readfile(uri)
      return readURI( t.resolve(uri) )
   end

   -- loadstring() : like the Lua standard loadstring function, except that
   -- the name is interpreted as the absolute URI of the chunk
   function t.loadstring(chunk, uri)
      uri = uri or "data:" .. chunk
      local locals = pmfuncs(uri, resolveURI, readURI, loaded, userGlobals)
      return loadstringwith(chunk, uri, locals, userGlobals)
   end

   -- loadfile() : like standard loadfile() except the name is a relative or
   -- absolute URI
   function t.loadfile(uri)
      local abs = t.resolve(uri)
      local str = readURI(abs)
      if not str then
         error("Error retrieving URI: " .. abs)
      end
      return t.loadstring( str, abs)
   end

   -- dofile() : like standard dofile() except the name is a relative or
   -- absolute URI
   function t.dofile(name)
      return assert(t.loadfile(name))()
   end

   -- require() : like standard require() except name is a relative or
   -- absolute URI
   function t.require(name)
      local abs = t.resolve(name)
      if not loaded[abs] then
         loaded[abs] = { t.dofile(abs) }
      end
      return table.unpack( loaded[abs] )
   end

   return t
end


pml.pmfuncs = pmfuncs
pml.loadstringwith = loadstringwith


return pml
