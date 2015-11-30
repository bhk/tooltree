
local function fib(n)
   local r
   if n <= 1 then
      r = n
   else
      r = fib(n-1) + fib(n-2)
   end
   print("fib(" .. n .. ") = " .. r)
   return r
end


local function funcB(str, num)
   local a, b, c, d, e, f, g, h, i, j, k, l
   num = num + fib(#str * 2)
   return num
end


local function example(arg1, arg2)
   debug.printf("Hello from example.lua...")
   debug.log(1, "str", _G)
   debug.pause()
   funcB("testing", arg1)
   return true
end

example(1, 2)
