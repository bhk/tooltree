local lpeg = require 'lpeg'

-- Lexing. {{{1

-- Construct a context for defining a lexer using LPeg.
local function buildLexer(language)

  -- Table of LPeg patterns to match all kinds of tokens.
  local patterns = {}
  local M = { language = language, patterns = patterns }

  -- Define a new token type given its name and LPeg pattern.
  local function define(name, patt)
    patt = lpeg.P(patt)
    patterns[name] = patt
    patterns[#patterns + 1] = name
  end

  -- Return an iterator that produces (kind, text) on each iteration.
  local any, keywords
  function M.gmatch(sources)
    local index = 1
    return function()
      if not any then any = compile() end
      local kind, text = any:match(sources, index)
      if kind and text then
        index = index + #text
        if keywords then
          kind = keywords[text] or kind
        end
        return kind, text
      end
    end
  end

  -- Compile all patterns into a single pattern that captures a (kind, text) pair.
  local function compile(_keywords)
    local function id(n) return lpeg.Cc(n) * lpeg.C(patterns[n]) end
    any = id(patterns[1])
    for i = 2, #patterns do any = any + id(patterns[i]) end
    keywords = _keywords
    return M
  end

  -- Return the two functions.
  return define, compile

end

return {
   buildLexer = buildLexer,
}

