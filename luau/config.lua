-- config.lua
--
-- Routines for finding and executing Lua-based config files.

local lfsu = require "lfsu"
local xpfs = require "xpfs"

local config = {}

local configMT = {}
function configMT:__index(k)
   return rawget(_G, k)
end

-- Mirror globals in the environment.
--
function config.initEnv(env)
   setmetatable(env, configMT)
end


-- Search for a file in the current directory and all parent directories.
-- If found, compile it and call it with 'env' as ts environment.
--
function config.find(name, env)
   if name == "" then
      return
   end

   local dir = xpfs.getcwd()
   if dir:match("^[a-zA-Z]%:\\") then
      dir = dir:gsub("\\", "/")
   end
   local path, found, chunk, succ, err, prevdir
   repeat
      path = lfsu.resolve(dir, name)
      local stat = xpfs.stat(path, "p")
      if stat then
         local perm = stat.perm
         if perm and perm:match("^r") then
            found = path
            break
         end
      end
      prevdir, dir = dir, lfsu.splitpath(dir)
   until dir == prevdir

   if found then
      chunk, err = loadfile(path, nil, env)
      if chunk then
         succ, err = pcall(chunk, path)
         if succ then
            err = nil
         end
      end
   end

   if err then
      error("config: error loading config file [".. path.."] ...\n" .. tostring(err))
   end

   return found
end

return config
