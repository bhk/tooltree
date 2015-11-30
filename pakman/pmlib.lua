-- pmlib
--
-- This library is exported to PAK files.
--

local pmuri = require "pmuri"

local pmlib = {}

----------------------------------------------------------------
-- Mapping functions: generate table of alternative local names
--    given a repository path.
----------------------------------------------------------------

function pmlib.mapLong(p)
   return { "/pakman" .. p.rootPath }
end


-- Return a list of "short" names for path (containing no slashes), ordered
-- from shortest to longest.  Short names include no slashes.  Ordering is
-- from most preferred to least preferred.  This algorithm returns the last
-- path element, followed by the last two concatenated with "-", etc., with
-- the following exceptions: 1) names listed in the 'junk' table are not
-- included in the most preferred choice, but they are added back in later
-- alternatives, and 2) names consisting only of digits and "." characters
-- are not considered adequate by themselves.
--
-- If a non-empty fragment is provided,
--
local function listShortNames(path, junk)
   local r = {}
   local g = {}
   local a, b, numSuffix

   junk = junk or {}
   while path do
      a,b = path:match("(.+)/([^/]+)")
      if not b then
         b = path:match("([^/]+)")
         if not b then
            break
         end
      end
      if not numSuffix and b:match("^%d") then
         numSuffix = "/" .. b
      elseif junk[b] then
         table.insert(g,b)
      else
         numSuffix = numSuffix or ""
         if r[1] then
            b = b .. "/" .. r[#r]
         end
         table.insert(r, b .. numSuffix)
         if g[1] then
            b = b .. "/" .. table.remove(g)
            table.insert(r, b .. numSuffix)
         end
         numSuffix = ""
      end
      path = a
   end
   return r
end


local junkDirs={ main=true, latest=true, dev=true, rel=true, head=true, tip=true }


function pmlib.mapShort(p)
   local t = listShortNames(p.rootPath, junkDirs)
   for k,v in ipairs(t) do
      t[k] = "/pkg/" .. v:gsub("/", "-")
   end
   return t
end


function pmlib.hash(str, len, alphabet)
   len = len or 5
   alphabet = alphabet or "0123456789abcdefghijkmnopqrstuvwxyz"

   -- (P+256)*M fits in floating point significand
   local P, M = 257, 8778946642047
   local h = 0
   for i = 1, #str do
      h = (h * P % M) + str:byte(i) + 1
   end

   local o = ""
   for i = 1, len do
      local d = (h % #alphabet) + 1
      o = o .. alphabet:sub(d,d)
      h = math.floor(h / #alphabet)
   end
   return o
end


----------------------------------------------------------------
-- "URI" functions:  Parse, generate, and combine Pakman URIs
----------------------------------------------------------------

pmlib.uriParse = pmuri.parse
pmlib.uriGen   = pmuri.gen

return pmlib
