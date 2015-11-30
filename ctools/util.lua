------------------------------------------------
-- util
------------------------------------------------

local U = {}

------------------------------------------------
-- File Utilities
------------------------------------------------

-- Remove redundant "./" and "x/../" occurrences
--
function U.CleanPathOld(path)

  path = path:gsub("\\", "/")

  while true do
     local a,b = path:match("^()%./()")

     if not a then
        a,b = path:match("()/%.()$")
     end
     if not a then
        a,b = path:match("()/%.()/")
     end
     if not a then
        a,b = path:match("()[^/]+/%.%.()$")
     end
     if not a then
        a,b = path:match("()[^/]+/%.%./()")
     end

     if not a then break end

     path = path:sub(1, a-1) .. path:sub(b, -1)
  end

  if path == "" then
     path = "."
  end

  return path
end

function U.CleanPath(path)
   path = "/" .. path:gsub("\\", "/") .. "/"
   repeat
      local oldpath = path
      path = path:gsub("/%./", "/")
   until path == oldpath

   local pos = 1
   while true do
      -- Replace   [pre/] parent/../ [post]   with  [pre/][post]
      local a, parent, b = path:match("()([^/]+)/()%.%./", pos)
      if not parent then
         break
      elseif parent == ".." then
         pos = b
      else
         path = path:sub(1,a-1) .. path:sub(b+3)
      end
   end

   path = path:sub(2,-2)
   return path ~= "" and path or "."
end


-- Resolve absolute or relative paths, given a current directory
--
function U.ResolvePath(dirName, ...)
   local t = {...}
   if dirName and dirName:sub(-1,-1) == "/" then
      dirName = dirName:sub(1,-2)
   end
   for i,path in ipairs(t) do
      if dirName and not (path:match("^[/\\]") or path:match("^%a:[/\\]")) then
	 path = dirName .. '/' .. path
      end
      t[i] = U.CleanPath(path)
   end
   return table.unpack(t)
end


------------------------------------------------
-- Misc Utilities
------------------------------------------------

-- Call f(k,v,x) for every k,v in tbl.  'x' is the value returned from the
-- previous call to f(), or 'val' when f() is first called.
--
function U.tfold(f, val, tbl)
   for k,v in pairs(tbl) do
      val = f(k,v,val)
   end
   return val
end

-- Count number of items in the table (not just array items)
--
function U.tcount(tbl)
   local b = 0
   for k in pairs(tbl) do
      b = b + 1
   end
   return b
end

-- Call f(v,x) for every array item in f.
--
function U.ifold(f, val, tbl)
   for k,v in ipairs(tbl) do
      val = f(v,val)
   end
   return val
end

-- Map over array.  Returns new array:  new[n] = f(old[n])
function U.imap(t,f)
   local t2 = {}
   for _,v in ipairs(t) do
      table.insert(t2, f(v))
   end
   return t2
end

-- Construct array from table:  each element = f(key,val)
function U.arrayFromTable(t,f)
   if type(f) == "string" then
      local f = "local a={} for k,v in pairs(...) do table.insert(a,"..f..")  end return a"
      return compile(f)(t)
   end

   local a = {}
   for k,v in pairs(t) do
      table.insert(a, f(k,v))
   end
   return a
end

-- Build table from array:  k,v = f(array_val)
function U.tableFromArray(t,f)
   local tt = {}
   for k,v in ipairs(t) do
      local kk,vv=f(k,v)
      tt[kk] = vv
   end
   return tt
end

-- ivalues
--
-- Like ipairs, but returns value,key instead of key,value.
--
function U.ivalues(array)
   local key = 0
   return function ()
             key = key + 1
             return array[key], key
          end
end


function U.tableEQ(a,b)
   for k,v in pairs(a) do
      if b[k] ~= v then return false end
   end
   for k,v in pairs(b) do
      if a[k] ~= v then return false end
   end
   return true
end


function U.TrimCR(line)
   if line:sub(-1,-1) == "\r" then
      return line:sub(1,-2)
   end
   return line
end

function U.fprintf(f, ...)
   f:write(string.format(...))
end

function U.printf(...)
   io.write(string.format(...))
end

function U.stringSplit(str, pat)
   local t = {}
   local pos = 1
   local max = #str + 1
   repeat
      local a,b = str:find(pat, pos)
      if not a then
	 a = max
	 b = max
      end
      table.insert(t, str:sub(pos, a-1))
      pos = b + 1
   until pos > max
   return t
end

function U.stringEnds(str, suffix)
   -- Avoid the non-linearity in string.sub() at offset zero
   --   string.sub(str, -1, -2)  -->  ""
   --   string.sub(str,  0, -1)  -->  str  (!)
   --
   return suffix == "" or str:sub(- #suffix, -1) == suffix
end

function U.stringBegins(str, prefix)
   return str:sub(1, #prefix) == prefix
end

return U
