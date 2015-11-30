local qt = require "qtest"
local SubStream = require "substream"

local eq = qt.eq


----------------
-- testStream

local testStream = {
   amt = 0,
}

function testStream:read(amt)
   self.amt = self.amt + amt
   return string.rep("A", amt)
end

function testStream:readable(task)
   task.cntReadable = task.cntReadable + 1
end


----------------

local function newTask()
   local task = {
      cntReady = 0,
      cntReadable = 0,
   }
   function task:ready()
      self.cntReady = self.cntReady + 1
   end
   return task
end


local ss = SubStream:new(testStream, "XYZ", 9)
local task = newTask()

-- >> when there is read-ahead data, readable() == ready()
ss:readable(task)
eq(task.cntReady, 1)

-- >> read(0) always returns ""
eq("", ss:read(0))

-- >> return read-ahead data first
eq("X", ss:read(1))
eq("YZ", ss:read(3))

-- >> after read-ahead is consumed, readable() should chain
ss:readable(task)
eq(task.cntReadable, 1)

-- >> return parent data after read-ahead data
eq("AAA", ss:read(3))
eq(testStream.amt, 3)

-- >> amount of data read from parent should be limited
eq("AAA", ss:read(4))
eq(testStream.amt, 6)

-- >> at end of SubStream, EOF should be indicated
eq(nil, ss:read(4))

-- >> at end of SubStream, readable() == ready()
ss:readable(task)
eq(task.cntReadable, 1)
eq(task.cntReady, 2)

-- >> read(0) always returns ""
eq("", ss:read(0))


-- >> drain / extract

local ss = SubStream:new(testStream, "XYZ", 9)
task = newTask()

local data = ""
repeat
   local d, err = ss:read(4)
   if d then
      data = data .. d
   end
until not d
eq(data, "XYZAAAAAA")

eq(ss:drain(), nil)
eq(ss:leftovers(), "")


-- >> when readAhead is larger than limit, substream returns limited data

local ss = SubStream:new(testStream, "ABCDEFG", 4)
task = newTask()
eq(ss:read(9), "ABCD")
eq(ss:drain(), nil)
eq(ss:leftovers(), "EFG")



