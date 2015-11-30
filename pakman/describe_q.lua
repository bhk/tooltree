local qt = require "qtest"
-- @require describe
local d, _d = qt.load("describe.lua", {"reverse", "sortTree", "asciiGraph"})

----------------------------------------------------------------
-- tests
----------------------------------------------------------------

function qt.tests.reverse()
   local function r(t)
      _d.reverse(t)
      return t
   end

   qt.eq( {},          r{} )
   qt.eq( {2},         r{2} )
   qt.eq( {9,8,7,6,5}, r{5,6,7,8,9} )
end


function qt.tests.visitTree()
   local tree = {
      a = { "b", "c", "d" },
      b = { "c", "e" },
      c = { "e" },
      d = { "c", "e" },
      e = { },
      f = { "d", "c", "b", "a"},
   }

   local v = _d.sortTree("f", function (node, f)
                                 for _,p in ipairs(tree[node]) do f(p) end
                              end)

   -- verify parent-first ordering
   local visited = {}
   for ndx,node in ipairs(v) do
      visited[node] = true
      -- make sure all children have not yet been visited
      for _,child in ipairs(tree[node]) do
         if visited[child] then
            error(qt.format("Parent/child (%s/%s) out of order!", node, child))
         end
      end
   end
end

----------------------------------------------------------------
-- example
----------------------------------------------------------------
local function example()
   local tree = {
      pakman = { "luau", "runlua", "maked", "simp4" },
      lfs    = { },
      lua    = { "maked" },
      runlua = { "lfs", "maked" },
      luau   = { "lua", "maked" },
      simp4  = { "lua", "maked" },
      maked  = { "a1/make.d" },
      ["a1/make.d"] = { },
   }

   -- populate children and name (as per Pakman data structures)
   for k,v in pairs(tree) do
      v.name = k
      v.children = {}
      for _,name in ipairs(v) do
         v.children[name] = tree[name]
      end
   end

   _d.asciiGraph(tree.pakman, io.write)
end

if arg[1] == "e" then
   example()
end

return qt.runTests()
