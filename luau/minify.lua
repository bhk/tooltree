-- minify

-- Parse Lua chunk, emitting stream of "plain", "string", and "comment" strings.
--
local function parse(txt, emit)
   local pos = 1            -- current position
   local pn                 -- beginning of next section
   local posend = #txt+1
   local ppos = {}   -- pattern -> position found (or #txt+1)

   local function find(pat)
      if (ppos[pat] or 0) < pos then
         ppos[pat] = txt:find(pat, pos) or posend
      end
      return ppos[pat]
   end

   local function produce(type)
      emit(type, txt:sub(pos, pn-1))
      pos = pn
   end

   local pS  = "[\"']"
   local pLS = "%[=*%["
   local pC  = "%-%-"
   local pLC = "%-%-%[=*%["

   while true do
      -- scan to next comment or string
      pn = math.min( find(pS), find(pLS), find(pC), find(pLC) )

      -- now: txt:(pos,pn-1) == plain
      if pn > pos then
         produce "plain"
      end

      -- now: pos == start of comment or string (or end)

      if pos == posend then
         return true
      elseif pos == ppos[pLS] then

         -- long string literal
         local eq = txt:match("%[(=*)%[", pos)
         assert(eq)
         pn = txt:match("%]"..eq.."%]()", pos)
         if not pn then
            return nil, "long string", pos
         end
         produce "string"

      elseif pos == ppos[pS] then

         -- regular string literal
         local q = txt:sub(pos,pos)
         local p = pos+1
         local pb
         repeat
            pb, pn = txt:match("()\\*"..q.."()", p)
            if not pn then
               return nil, "string", pos
            end
            p = pn
         until not pn or (pn - pb) % 2 == 1
         pn = pn or #txt
         produce "string"

      elseif pos == ppos[pLC] then

         -- long comment
         local eq = txt:match("%[(=*)%[", pos)
         assert(eq)
         pn = txt:match("%]"..eq.."%]()", pos)
         if not pn then
            return nil, "long comment", pos
         end
         produce "comment"

      elseif pos == ppos[pC] then

         -- single-line comment: includes "\n" unless at end of file
         pn = (txt:match("\n()", pos) or #txt+1)
         produce "comment"

      end
   end
end


-- Reduce comments to whitespace with equivalent number of line breaks
--
local function strip(txt)
   local o = {}

   local function emit(typ, str)
      if typ == "comment" then
         str = str:gsub("[^\n]*", "")
         if str == "" then str = " " end
      elseif typ == "plain" then
         str = str:match("[ \t]*(.-)[ \t]*$")
         str = str:gsub("[ \t]+([^_%w])", "%1")
         str = str:gsub("([^%w_])[ \t]+", "%1")
         str = str:gsub("[ \t]+", " ")
      end
      table.insert(o, str)
   end

   local succ, err, pos = parse(txt, emit)
   if not succ then
      return nil, err, pos
   end
   return table.concat(o)
end


return {
   parse = parse,
   strip = strip,
}
