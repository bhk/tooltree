local lex  = require 'smarklex'
local lpeg = require 'lpeg'

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
local endline  = S'\r\n\f'
local slc = '//' * (1 - endline)^0
local mlc = '/*' * (1 - P'*/')^0 * '*/'
define('comment', slc + mlc)

-- Operators (matched after comments because of conflict with minus).
define('operator', P'!=' + P'!' + P'&&' + P'||' + P'++' + 
  P'+=' + P'-=' + P'*=' + P'/=' + P'>>=' + P'<<=' + P'>>>=' + P'&=' +
  P'|=' + P'^=' + P'>>>' +
  P'===' + P'==' + P'>=' + P'<=' + P'or' + S']{=>^[<;)*(%}+-~|%?:,/.#')

-- Define an `error' token kind that consumes one character and enables
-- the lexer to resume as a last resort for dealing with unknown input.
define('error', 1)

-- Words that are not identifiers (operators and keywords).
local lexer = compile {
  ['break'     ] = 'keyword',
  ['catch'     ] = 'keyword',
  ['continue'  ] = 'keyword',
  ['do'        ] = 'keyword',
  ['else'      ] = 'keyword',
  ['export'    ] = 'keyword',
  ['false'     ] = 'constant',
  ['for'       ] = 'keyword',
  ['function'  ] = 'keyword',
  ['if'        ] = 'keyword',
  ['import'    ] = 'keyword',
  ['in'        ] = 'keyword',
  ['instanceOf'] = 'keyword',
  ['label'     ] = 'keyword',
  ['let'       ] = 'keyword',
  ['new'       ] = 'keyword',
  ['not'       ] = 'keyword',
  ['null'      ] = 'constant',
  ['repeat'    ] = 'keyword',
  ['return'    ] = 'keyword',
  ['switch'    ] = 'keyword',
  ['this'      ] = 'keyword',
  ['throw'     ] = 'keyword',
  ['true'      ] = 'constant',
  ['try'       ] = 'keyword',
  ['typeof'    ] = 'keyword',
  ['until'     ] = 'keyword',
  ['var'       ] = 'keyword',
  ['void'      ] = 'keyword',
  ['while'     ] = 'keyword',
  ['with'      ] = 'keyword',
  ['yield'     ] = 'keyword',
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

