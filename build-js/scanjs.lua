-- scanjs.lua
--

local lpeg = require "lpeg"
local P, R, S = lpeg.P, lpeg.R, lpeg.S
local C, Cs = lpeg.C, lpeg.Cs

local commentHandler

local function processComment(text)
   if commentHandler then
      commentHandler(text)
   end
end

local any = P(1)

local nl = P("\r\n") + P("\n")

local comment = "/*" * (any - "*/")^0 * "*/"
              + "//" * ( (any - nl)^0 / processComment )

local space = " " + nl + comment

local ws = space ^ 0

local function T(pat)
   return pat * ws
end

local ident = T( C( R("az", "AZ", "__", "$$") *
                    R("az", "AZ", "__", "$$", "09")^0 ) )

local literalString =
   T("'" * Cs(( (any - "'") + (P"\\"/"")*any )^0) * "'" +
     '"' * Cs(( (any - '"') + (P"\\"/"")*any )^0) * '"')

local funCall = ident * T"(" * literalString * T")"

local member = '.' * ws * ident


-- Scan JavaScript source and return a table `o`:
--
--  o.requires = array of JavaScript module names passed to `require(...)`
--  o.title = value associated with "title" in a single-line comment
--
local function scan(source)
   local o = {}

   local requires = {}
   local function doFunCall(name, stringArg)
      if name == "require" then
         table.insert(requires, stringArg)
      end
   end

   commentHandler = function (text)
      local title = text:match(" *title: +(.*)")
      if title then
         o.title = title
      end
   end

   local JS = (funCall / doFunCall + member + ident + space^1 + any)^0
   JS:match(source)

   commentHandler = nil

   o.requires = requires
   return o
end


return {
   scan = scan,

   -- export for testing:
   space = space,
   ws = ws,
   funCall = funCall
}
