local lex  = require 'smarklex'
local lpeg = require 'lpeg'

--[[

 Lexer for Lua 5.1 source code powered by LPeg.

 Author: Peter Odding <peter@peterodding.com>
 Modified by: Greg Fitzgerald <garious@gmail.com>
 Branched at: January 14, 2011
 URL: http://peterodding.com/code/lua/lxsh/

]]

local C = lpeg.C
local Cc = lpeg.Cc
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S
local D = R'09'
local I = R('AZ', 'az', '\127\255') + P'_'

-- Create a lexer definition context.
local define, compile = lex.buildLexer 'lua'

-- Pattern definitions start here.
define('whitespace', S'\r\n\f\t '^1)
define('constant', P'true' + P'false' + P'nil')
define('identifier', I * (I + D + '.')^0)

-- Numbers.
local sign = S'+-'^-1
local decimal = D^1
local hexadecimal = P'0' * S'xX' * R('09', 'AF', 'af') ^ 1
local float = (D^1 * P'.' * D^0 + P'.' * D^1) * (S'eE' * sign * D^1)^-1
define('number', hexadecimal + float + decimal)

-- Pattern for long strings and long comments.
local longstring = #(P'[[' + (P'[' * P'=' ^ 0 * P'[')) * P(function(input, index)
  local level = input:match('^%[(=*)%[', index)
  if level then
    local _, stop = input:find(']' .. level .. ']', index, true)
    if stop then return stop + 1 end
  end
end)

-- String literals.
local singlequoted = P"'" * ((1 - S"'\r\n\f\\") + (P'\\' * 1))^0 * "'"
local doublequoted = P'"' * ((1 - S'"\r\n\f\\') + (P'\\' * 1))^0 * '"'
define('string', singlequoted + doublequoted + longstring)

-- Comments.
local eol = P'\r\n' + P'\n'
local line = (1 - S'\r\n\f')^0 * eol^-1
local soi = P(function(s, i) return i == 1 and i end)
local shebang = soi * '#!' * line
local singleline = P'--' * line
local multiline = P'--' * longstring
define('comment', multiline + singleline + shebang)

-- Operators (matched after comments because of conflict with minus).
define('operator', P'not' + P'...' + P'and' + P'..' + P'~=' +
  P'==' + P'>=' + P'<=' + P'or' + S']{=>^[<;)*(%}+-:,/.#')

-- Define an `error' token kind that consumes one character and enables
-- the lexer to resume as a last resort for dealing with unknown input.
define('error', 1)

-- Words that are not identifiers (operators and keywords).
local lexer = compile {
  ['and'     ] = 'operator',
  ['break'   ] = 'keyword',
  ['do'      ] = 'keyword',
  ['else'    ] = 'keyword',
  ['elseif'  ] = 'keyword',
  ['end'     ] = 'keyword',
  ['false'   ] = 'constant',
  ['for'     ] = 'keyword',
  ['function'] = 'keyword',
  ['if'      ] = 'keyword',
  ['in'      ] = 'keyword',
  ['local'   ] = 'keyword',
  ['nil'     ] = 'constant',
  ['not'     ] = 'operator',
  ['or'      ] = 'operator',
  ['repeat'  ] = 'keyword',
  ['return'  ] = 'keyword',
  ['then'    ] = 'keyword',
  ['true'    ] = 'constant',
  ['until'   ] = 'keyword',
  ['while'   ] = 'keyword',
}

local append = table.insert

return function(node, doc)
   local E = require("smarklib").E
   local styleMap = require("codestyle")
   local t = {}
   for k,v in lexer.gmatch(node.text) do
      append(t, styleMap[k] and E.span{v, style=styleMap[k]} or v)
   end
   return E.pre(t)
end

