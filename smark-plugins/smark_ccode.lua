--[[

 Lexer for C source code powered by LPeg.

 Author: Peter Odding <peter@peterodding.com>
 Modified by: Greg Fitzgerald <garious@gmail.com>
 Branched at: January 14, 2011
 URL: http://peterodding.com/code/lua/lxsh/

]]

local lex  = require 'smarklex'
local lpeg = require 'lpeg'
local C = lpeg.C
local Cc = lpeg.Cc
local P = lpeg.P
local R = lpeg.R
local S = lpeg.S

-- Create a lexer definition context.
local define, compile = lex.buildLexer 'c'

-- The following LPeg patterns are used as building blocks.
local upp, low = R'AZ', R'az'
local oct, dec = R'07', R'09'
local hex      = dec + R'AF' + R'af'
local letter   = upp + low
local alnum    = letter + dec + '_'
local endline  = S'\r\n\f'
local newline  = '\r\n' + endline
local escape   = '\\' * ( newline
                        + S'\\"\'?abfnrtv'
                        + (#oct * oct^-3)
                        + ('x' * #hex * hex^-2))

-- Pattern definitions start here.
define('whitespace' , S'\r\n\f\t\v '^1)
define('identifier', (letter + '_') * alnum^0)
define('preprocessor', P'#' * (P'define' + 'include' + 'ifndef' + 'ifdef' + 'endif' + 'if' + 'else' + 'pragma'))

-- Character and string literals.
local chr = "'" * ((1 - S"\\\r\n\f'") + escape) * "'"
local str = '"' * ((1 - S'\\\r\n\f"') + escape)^0 * '"'
define('string', chr + str)

-- Comments.
local slc = '//' * (1 - endline)^0
local mlc = '/*' * (1 - P'*/')^0 * '*/'
define('comment', slc + mlc)

-- Operators (matched after comments because of conflict with slash/division).
define('operator', P'>>=' + '<<=' + '--' + '>>' + '>=' + '/=' + '==' + '<='
    + '+=' + '<<' + '*=' + '++' + '&&' + '|=' + '||' + '!=' + '&=' + '-='
    + '^=' + '%=' + '->' + S',)*%+&(-~/^]{}|.[>!?:=<;')

-- Numbers.
local int = (('0' * ((S'xX' * hex^1) + oct^1)) + dec^1) * S'lL'^-2
local flt = ((dec^1 * '.' * dec^0
            + dec^0 * '.' * dec^1
            + dec^1 * 'e' * dec^1) * S'fF'^-1)
            + dec^1 * S'fF'
define('number', flt + int)

-- Define an `error' token kind that consumes one character and enables
-- the lexer to resume as a last resort for dealing with unknown input.
define('error', 1)

local lexer = compile {
   ['auto'    ] = 'keyword',
   ['break'   ] = 'keyword',
   ['case'    ] = 'keyword',
   ['char'    ] = 'keyword',
   ['const'   ] = 'keyword',
   ['continue'] = 'keyword',
   ['default' ] = 'keyword',
   ['do'      ] = 'keyword',
   ['double'  ] = 'keyword',
   ['else'    ] = 'keyword',
   ['enum'    ] = 'keyword',
   ['extern'  ] = 'keyword',
   ['float'   ] = 'keyword',
   ['for'     ] = 'keyword',
   ['goto'    ] = 'keyword',
   ['if'      ] = 'keyword',
   ['int'     ] = 'keyword',
   ['long'    ] = 'keyword',
   ['register'] = 'keyword',
   ['return'  ] = 'keyword',
   ['short'   ] = 'keyword',
   ['signed'  ] = 'keyword',
   ['sizeof'  ] = 'keyword',
   ['static'  ] = 'keyword',
   ['struct'  ] = 'keyword',
   ['switch'  ] = 'keyword',
   ['typedef' ] = 'keyword',
   ['union'   ] = 'keyword',
   ['unsigned'] = 'keyword',
   ['void'    ] = 'keyword',
   ['volatile'] = 'keyword',
   ['while'   ] = 'keyword',

   -- Exception Macros
   ['TRY'     ] = 'macro',
   ['THROW'   ] = 'macro',
   ['THROW_IF'] = 'macro',
   ['CATCH'   ] = 'macro',
   ['ASSERT'  ] = 'macro',
   
   -- MFO Macro Language
   ['MFO_CREATE']                 = 'macro',
   ['MFO_DEFINE']                 = 'macro',
   ['MFO_INHERIT_IFACE']          = 'macro',
   ['MFO_INHERIT_FACET']          = 'macro',
   ['MFO_INHERIT_FACET_IFACE']    = 'macro',
   ['MFO_DECLARE_IFACE']          = 'macro',
   ['MFO_DECLARE_FACET']          = 'macro',
   ['MFO_DECLARE_FACET_IFACE']    = 'macro',
   ['MFO_FACET_DEINIT']           = 'macro',
   ['MFO_DEINIT']                 = 'macro',
   ['MFO_BEGIN_FACET_IFACE']      = 'macro',
   ['MFO_END_FACET_IFACE']        = 'macro',
   ['MFO_BEGIN_IFACE']            = 'macro',
   ['MFO_END_IFACE']              = 'macro',
   ['MFO_BEGIN_FACET_IFACE']      = 'macro',
   ['MFO_BEGIN_FACET_IFACE_NOQI'] = 'macro',
   ['MFO_END_FACET_IFACE']        = 'macro',
   ['MFO_BEGIN_IFACES']           = 'macro',
   ['MFO_END_IFACES']             = 'macro',
   ['MFO_IID']                    = 'macro',
   ['MFO_FACET_IID']              = 'macro',
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

