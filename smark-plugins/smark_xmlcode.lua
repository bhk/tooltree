local lex  = require 'smarklex'
local lpeg = require 'lpeg'

--[[
]]

local C  = lpeg.C
local Cc = lpeg.Cc
local P  = lpeg.P
local R  = lpeg.R
local S  = lpeg.S
local D  = R('09')
local I  = R('AZ', 'az', '\127\255') + P('_') + D

-- Create a lexer definition context.
local define, compile = lex.buildLexer 'lua'

-- Pattern definitions start here.
define('whitespace', S('\r\n\f\t ')^1)
define('identifier', I * (I + D)^0 - P('rem'))
       

-- Numbers.
local sign = S('+-')^-1
local decimal = D^1
local hexadecimal = P('0') * S('xX') * R('09', 'AF', 'af') ^ 1
local float = (D^1 * P'.' * D^0 + P'.' * D^1) * (S('eE') * sign * D^1)^-1
define('number', hexadecimal + float + decimal)

-- String literals.
local singlequoted = P"'" * ((1 - S"'\r\n\f\\") + (P'\\' * 1))^0 * "'"
local doublequoted = P'"' * ((1 - S'"\r\n\f\\') + (P'\\' * 1))^0 * '"'
define('string', singlequoted + doublequoted)

-- Comments
local eol        = P('\r\n') + P('\n')
local line       = (1 - S('\r\n\f'))^0 * eol^-1
local singleline = P('<!--') * (1 - P('-->'))^1 * P('-->')
define('comment', singleline)

-- Keywords
define('keyword',
       (P('<') * I^1 * P('>'))
          + (P('</') * I^1 * P('>'))
          + (P('<') * I^1 * P('/>'))
          + (P('<') * I^1 * P(' '))
          + P('>'))


-- Define an `error' token kind that consumes one character and enables
-- the lexer to resume as a last resort for dealing with unknown input.
define('error', 1)



local lexer = compile {
}


local append = table.insert

return function(node, doc)
   local E = require("smarklib").E
   local styleMap = require("codestyle")
   local t = {}
   for k,v in lexer.gmatch(node.text) do
      append(t, styleMap[k] and E.span{v, style=styleMap[k]} or v)
      -- print(k, v)
   end
   return E.pre(t)
end
