-- lua52.lua: Provide Lua 5.2-style APIs on Lua 5.1

if not loadstring then
   return -- not running on Lua 5.1
end

-- unpack moves to table.unpack

table.unpack = unpack
table.pack = function (...)
                return { n = select('#',...), ...}
             end

-- load obsoletes loadstring & setfenv

local _loadstring, _loadfile = loadstring, loadfile

function load(t, s, _, env)
   local f, err = _loadstring(t, s)
   if f and env then
      setfenv(f, env)
   end
   return f, err
end

function loadfile(filename, _, env)
   local f, err = _loadfile(filename)
   if f and env then
      setfenv(f, env)
   end
   return f, err
end

-- package.loaders moves to package.searchers

package.searchers = package.loaders


-- os.execute returns better information

local _os_execute = os.execute

function os.execute(cmd)
   -- when called without a command returns 'true' if a shell is available
   if not cmd then
      return true
   end

   local r = _os_execute(cmd)
   if r ~= 0 then
      local code = r>=256 and math.floor(r/256) or r
      return nil, "exit", code
   else
      return true, "exit", 0
   end
end

-- xpcall accepts additional arguments

local _xpcall = xpcall

function xpcall(fn, msgf, ...)
   local a = table.pack(...)
   local function f2()
      return fn(table.unpack(a, 1, a.n))
   end
   return _xpcall(f2, msgf)
end
