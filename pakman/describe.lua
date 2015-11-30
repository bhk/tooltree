-- decribe.lua  Describe PM packages
--
local pmuri = require "pmuri"
local pmlib = require "pmlib"

-- Reverse an array
--
local function reverse(a)
   local min, max = 1, #a
   while min < max do
      a[min], a[max] = a[max], a[min]
      min, max = min+1, max-1
   end
end


-- Create a partially-ordered array of nodes: parents precede children
--
local function sortTree(top, mapChildren)
   local list = {}
   local visited = {}

   local function v(node)
      if visited[node] then return end
      visited[node] = true
      mapChildren(node, v)
      table.insert(list, node)
   end
   v(top)
   reverse(list)
   return list
end


-- Sort tree of PM packages such that parents precede children
--
local function sortPackages(top)
   -- construct partially ordered list of all packages (descendants first)
   local function mapChildren(pkg,f)
      for _,c in pairs(pkg.children) do f(c) end
   end
   return sortTree(top, mapChildren)
end


-- Output a "Kelley-style"? dependency graph in ASCII art format
--
local function asciiGraph(top, o)
   local list = sortPackages(top)
   local tails = {}
   for _, p in ipairs(list) do
      -- compute this package's tail: vertical backbone & horizontal spurs
      local tail = {}
      for k,v in pairs(p.children) do
         tail[v] = true
      end

      -- place package in tree
      local name = p.name or p.uri
      local wid = #name
      for _,row in ipairs{",", "+", "`"} do
         for _,tail in ipairs(tails) do
            if row == "+" and tail[p] then
               o("  +-> ")
               tail[p] = nil
            elseif next(tail) then
               o("  |   ")
            else
               o("      ")
            end
         end
         if row == "+" then
            o( string.format("| %-" .. wid .. "s |%s\n", name, (p.commands.make and " *" or "")) )
         else
            local pl = (row == "`" and next(tail)) and "+" or "-"
            o( string.format("%s-%s%s%s\n", row, pl, string.rep("-", wid), row))
         end
      end

      -- track this tail
      table.insert(tails, tail)

      -- trim unused tails
      for ndx = #tails, 1, -1 do
         if next(tails[ndx]) then break end
         table.remove(tails, ndx)
      end
   end

   return list
end


-- assign short but not conflicting names to packages
-- used = { used_names -> true }
--
local function assignNames(top)
   local pkgs = sortPackages(top)  -- order is not important; we just want an array
   local used = {}

   for _,p in ipairs(pkgs) do
      local u, fragment = p.uri:match("([^#%?@]*)[^%?]*%??([^#]*)")
      local path = u:match("(.-)/%.%.%.$") or u:match("(.-)[/%.]pak$") or u
      local shorts = pmlib.mapShort{ rootPath = path }

      fragment = fragment or ""
      if fragment ~= "" then
         fragment = " (" .. pmuri.pctDecode(fragment) .. ")"
      end

      for _, name in ipairs(shorts) do
         name = name:gsub("^/pkg/", "") .. fragment
         if not used[name] then
            u = name
            break
         end
      end
      p.name = u
      used[u] = true
   end
end


local function pf(...)
   io.write(string.format(...))
end

local function attr(p, attr)
   pf("    %s: %s\n", attr, p[attr] or "-undefined-")
end

local function describePackage(p)
   attr(p, "uri")
   attr(p, "root")
   if p.result ~= "." then
      attr(p, "result")
   end

   if p.files[2] or p.files[1] ~= "..." then
      pf("\n    Files retrieved:\n")
      for _,pat in ipairs(p.files) do
         pf("     * %s\n", pat)
      end
   end

   if next(p.children) then
      pf("\n    Dependencies:\n")
      for name,dep in pairs(p.children) do
         pf("     * %s -> %s\n", name, dep.name)
      end
   end

   pf("\n")
end


-- wr : write indented lines
local indent = "    "
local startingIndent = indent
local function wr(s)
   io.write(startingIndent .. s:gsub("\n(.)", "\n"..indent.."%1"))
   startingIndent = (s:sub(-1) == "\n") and indent or ""
end


local function describe(top)
   assignNames(top)

   local list = asciiGraph(top, wr)
   pf("\n")

   -- Use env var until command-line vars are supported
   if (os.getenv("describe_v") or "") ~= "" then

      pf("Project Tree\n")
      pf("============\n\n")

      -- ...asciiGraph...

      pf("Packages\n")
      pf("========\n\n")

      for _,p in ipairs(list) do
         pf("%s\n%s\n\n", p.name, string.rep("-", #p.name))
         describePackage(p)
      end
   end
end


return {
   describe = describe,
}
