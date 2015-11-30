-- sample target program used by mdbagent_q.lua

local t = {}

function t.fail(n)
   if n > 1 then
      t.fail(n-1)
   end
   return (nil)()
end

function t.ok()
   print(arg[0], arg[1], arg[2], #arg)
end

return ( t[arg[1]](4) )
