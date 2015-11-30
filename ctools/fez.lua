-- fez : parse files that describe compiled object file contents/sizes

local fez = {}

local function bitIsSet(b, val)
   return (val - val%b) % (b*2) == b
end

fez.bitIsSet = bitIsSet

-- Parse files that describe object file contents/sizes
--
function fez.read(text)

   -- Try ARM "fromelf -z" output

   local code,d,ro,rw,zi =
      text:match("RO Data%s*RW Data%s*ZI Data%s*Debug%s*%w+ Name%s*(%d*)%s*(%d*)%s*(%d*)%s*(%d*)%s*(%d*)")

   -- Try UNIX "size" output for ELFs

   if not code then
      ro,d = 0,0   -- can't tell code from roData
      code,rw,zi =
	 text:match("text%s*data%s*bss%s*dec%s*hex%s*filename%s*(%d+)%s*(%d+)%s*(%d+)")
   end

   -- Try OSX "size" output for Mach-O executables

   if not code then
      ro,d,zi = 0,0,0  -- can't tell code from roData
      code,rw =
	 text:match("%s*__TEXT%s+__DATA%s[^\n]*\n%s*(%d+)%s+(%d+)%s")
   end

   -- Try "dumpbin /headers" output

   if not code and text:match("Dumper.*FILE HEADER VALUES") then
      code,d,ro,rw,zi = 0,0,0,0,0

      local CODE                 = 0x00000020  -- code.
      local INITIALIZED_DATA     = 0x00000040  -- initialized data.
      local UNINITIALIZED_DATA   = 0x00000080  -- uninitialized data.

      for size,flags in text:gmatch("SECTION HEADER.-(%x*) size .-(%x*) flags") do
	 size = tonumber(size, 16)
	 flags = tonumber(flags, 16)
	
	 if bitIsSet(CODE, flags)               then code = code + size end
	 if bitIsSet(INITIALIZED_DATA, flags)   then rw = rw + size end
	 if bitIsSet(UNINITIALIZED_DATA, flags) then zi = zi + size end
      end
   end

   if code then
      local rom = code + ro + rw
      local ram = rw + zi
      return rom, ram, tonumber(code), tonumber(d), tonumber(ro), tonumber(rw), tonumber(zi)
   end
end

return fez
