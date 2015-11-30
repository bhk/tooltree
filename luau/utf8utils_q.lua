-- utf8_q.lua

local qt = require "qtest"
local utf8utils = require "utf8utils"

local eq = qt.eq
local char = string.char

local function expectError(pat, f, ...)
   local succ, err = pcall( f, ... )
   qt._eq(false, succ, 2)
   qt._eq("string", type(err), 2)
   if not err:match(pat) then
      local e = string.format("Test Failure\nNo '%s' in error message: %s\n",
                              pat, err)
      error(e, 2)
   end
end


function qt.tests.encodeDecode()

   local function t(str, val)
      qt._eq(str, utf8utils.encode(val), 2)
      qt._eq(val, utf8utils.decode(str), 2)
   end

   t( char(0),                      0 )
   t( char(0x7F),                   0x7F )
   t( char(0xC2, 0x80),             0x80 )
   t( char(0xDF, 0xBF),             0x7FF )
   t( char(0xE0, 0xA0, 0x80),       0x800 )
   t( char(0xEF, 0xBF, 0xBF),       0xFFFF )
   t( char(0xF0, 0x90, 0x80, 0x80), 0x10000 )
   t( char(0xF4, 0x8F, 0xBF, 0xBF), 0x10FFFF )

   expectError("invalid", utf8utils.decode, char(0x80) )

   eq("1\192\129",
      utf8utils.decode("\192\129", function (n,s) return n .. s end))
end


function qt.tests.validate()
   eq(nil, (utf8utils.validate("abc\194\129")))
   expectError("invalid", utf8utils.validate, char(0x80))
end


function qt.tests.mbpattern()
   -- Pattern should:
   --   1. match valid multi-byte sequences
   --   2. match all invalid utf-8 single- or multi-byte sequences
   eq( "(\194\129)a(\128)(\194\128)(\192\129)b(\224)c",
       (string.gsub("\194\129a\128\194\128\192\129b\224c", utf8utils.mbpattern, "(%1)")) )
end


function qt.tests.bin()
   local bin = "a\127\128\255c"
   local chr = "a\127"..utf8utils.encode(128)..utf8utils.encode(255).."c"

   eq( chr, utf8utils.binToChars(bin) )
   eq( bin, utf8utils.charsToBin(chr) )
end


-- Time alternative implementations
--
-- local byte = string.byte
-- local char = string.char
-- local s = "\195\128"
--
-- require("clocker"):compare{
--    function ()
--       return char( (byte(s)-194)*64 + byte(s,2) )
--    end,
--
--    function ()
--       local n = byte(s,2)
--       if byte(s,1) == 195 then
--          return char(n + 64)
--       end
--       return char(n)
--    end
-- }

return qt.runTests()
