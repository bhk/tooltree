local qt = require "qtest"
local fez = require "fez"

local eq = qt.eq

function qt.tests.bitIsSet()
   assert( not fez.bitIsSet( 4, 40) )
   assert(     fez.bitIsSet( 8, 40) )
   assert( not fez.bitIsSet(16, 40) )
   assert(     fez.bitIsSet(32, 40) )
   assert( not fez.bitIsSet(64, 40) )
end

function qt.tests.readFez_fromelf()
   -- ARM "fromelf -z" output

   local input = [[
... stuff ..
** Object/Image Component Sizes


      Code  (inc. data)  RO Data    RW Data    ZI Data      Debug   File Name

       788         10         40          1          2        176   x.o
   ]]

   local rom, ram, code, d, ro, rw, zi = fez.read(input)

   eq(829, rom)
   eq(3, ram)
   eq(788, code)
   eq(10, d)
   eq(40, ro)
   eq(1, rw)
   eq(2, zi)
end


function qt.tests.readFez_fromelf40()
   -- RVCT 4.0 format
   local input = [[

** Object/Image Component Sizes

      Code (inc. data)   RO Data    RW Data    ZI Data      Debug   Object Name

        16          8          4          2          1         32   RVCT40arm9_Release/AEEBase.o
]]

   local rom, ram, code, d, ro, rw, zi = fez.read(input)

   eq(22, rom)
   eq(3, ram)
   eq(16, code)
   eq(8, d)
   eq(4, ro)
   eq(2, rw)
   eq(1, zi)
end

function qt.tests.readFez_size()
   -- UNIX 'size'

   local input = [[
   text    data     bss     dec     hex filename
    777       1       2     791     a10 x.o
   ]]

   local rom, ram, code, d, ro, rw, zi = fez.read(input)

   eq(778, rom)
   eq(3, ram)
   eq(777, code)
   eq(0, d)
   eq(0, ro)
   eq(1, rw)
   eq(2, zi)
end

function qt.tests.readFez_sizeOSX()
   -- OSX "size" See "man size" and
   -- http://developer.apple.com/documentation/DeveloperTools/Conceptual/MachORuntime/Reference/reference.html
   -- Unfortunately, the __DATA segment mixes const and non-const.  At the
   -- section level (using "size -m") we could identify __DATA.__const as
   -- 'const', but still __DATA.__bss would be ambiguous (const vs. non-const).

   local inputOSX = [[
__TEXT	__DATA	__OBJC	others	dec	hex
1613	576	0	8714	10903	2a97
]]

   local rom, ram, code, d, ro, rw, zi = fez.read(inputOSX)

   eq(1613+576, rom)
   eq(576, ram)
   eq(1613, code)
   eq(0, d)
   eq(0, ro)
   eq(576, rw)
   eq(0, zi)
end


function qt.tests.readFez_dumpbin()
   -- Microsoft COFF/PE Dumper ("dumpbin")

   local input = [[
Microsoft (R) COFF/PE Dumper Version 7.10.3077
Copyright (C) Microsoft Corporation.  All rights reserved.


Dump of file t.obj

File Type: COFF OBJECT

FILE HEADER VALUES
             14C machine (x86)
               6 number of sections
        462942F9 time date stamp Fri Apr 20 15:47:21 2007
             277 file pointer to symbol table
              14 number of symbols
               0 size of optional header
               0 characteristics

SECTION HEADER #1
.drectve name
       0 physical address
       0 virtual address
      2A size of raw data
     104 file pointer to raw data (00000104 to 0000012D)
       0 file pointer to relocation table
       0 file pointer to line numbers
       0 number of relocations
       0 number of line numbers
  100A00 flags
         Info
         Remove
         1 byte align

SECTION HEADER #2
.debug$S name
       0 physical address
       0 virtual address
      5D size of raw data
     12E file pointer to raw data (0000012E to 0000018A)
       0 file pointer to relocation table
       0 file pointer to line numbers
       0 number of relocations
       0 number of line numbers
42100040 flags
         Initialized Data
         Discardable
         1 byte align
         Read Only

SECTION HEADER #3
   .data name
       0 physical address
       0 virtual address
      64 size of raw data
     18B file pointer to raw data (0000018B to 000001EE)
       0 file pointer to relocation table
       0 file pointer to line numbers
       0 number of relocations
       0 number of line numbers
C0400040 flags
         Initialized Data
         8 byte align
         Read Write

SECTION HEADER #4
  .rdata name
       0 physical address
       0 virtual address
      64 size of raw data
     1EF file pointer to raw data (000001EF to 00000252)
       0 file pointer to relocation table
       0 file pointer to line numbers
       0 number of relocations
       0 number of line numbers
40400040 flags
         Initialized Data
         8 byte align
         Read Only

SECTION HEADER #5
   .text name
       0 physical address
       0 virtual address
      10 size of raw data
     253 file pointer to raw data (00000253 to 00000262)
     263 file pointer to relocation table
       0 file pointer to line numbers
       2 number of relocations
       0 number of line numbers
60500020 flags
         Code
         16 byte align
         Execute Read

SECTION HEADER #6
    .bss name
       0 physical address
       0 virtual address
      64 size of raw data
       0 file pointer to raw data
       0 file pointer to relocation table
       0 file pointer to line numbers
       0 number of relocations
       0 number of line numbers
C0400080 flags
         Uninitialized Data
         8 byte align
         Read Write

  Summary

          64 .bss
          64 .data
          5D .debug$S
          2A .drectve
          64 .rdata
          10 .text
   ]]

   local rom, ram, code, d, ro, rw, zi = fez.read(input)

   eq(309 ,rom)
   eq(393, ram)
   eq(16, code)
   eq(0, d)
   eq(0, ro)
   eq(293, rw)
   eq(100, zi)
end

return qt.runTests()
