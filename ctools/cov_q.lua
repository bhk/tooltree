-- Test cov.lua

local qt = require "qtest"
local Cov = require "cov"

local eq = qt.eq

function qt.tests.csv_load()
   local cov = Cov.new()
   cov:loadText("#csv file,linesExecutable,linesExecuted,pctExecuted,lct\n" ..
                   "../../b/../a.c,5,1,20,:0:0:1:0:0:\n")

   eq(cov[1].file, "../../a.c")
end


function qt.tests.csv_merge()
   local cov = Cov.new()
   cov:loadText("#csv file,linesExecutable,linesExecuted,pctExecuted,lct\n" ..
                "a.c,5,1,20,:0:0:1:0:0:\n")

   cov:loadText("#csv file,linesExecutable,linesExecuted,pctExecuted,lct\n" ..
                "a.c,5,2,40,:1:1:0:0:0:\n")

   cov:deriveFields({})

   local row = cov[1]
   qt.assert(row)
   eq(row.lct, ":1:1:1:0:0")
   eq(row.pctExecuted, 60)
end


local xmlInput = [[
ÅÔÅªÅø<?xml version="1.0" encoding="utf-8"?>
<sessionFile xmlns="http://www.compuware.com/devpartner/schema">
  <summary>
    <exePath>a.exe</exePath>
    <cmdArgs></cmdArgs>
    <exitCode>0</exitCode>
    <creationDate>11/17/2006 12:36:36 AM</creationDate>
    <creator>DevPartner Coverage Analysis - Manual Merge</creator>
    <startDate>Thursday, November 16, 2006</startDate>
    <startTime>4:25:09 PM</startTime>
    <endDate>Thursday, November 16, 2006</endDate>
    <endTime>4:25:13 PM</endTime>
    <procSpeed>1683 Mhz</procSpeed>
    <procCount>1</procCount>
    <speedStepDisabled>True</speedStepDisabled>
    <osVersion>Microsoft Windows 2000</osVersion>
  </summary>
  <images>
    <coverageData>
      <pctLinesExecuted>64.2545</pctLinesExecuted>
      <numLines>26339</numLines>
      <numLinesExecuted>16924</numLinesExecuted>
      <numLinesNotExecuted>9415</numLinesNotExecuted>
      <pctMethodsExecuted>70.2847</pctMethodsExecuted>
      <numMethods>2248</numMethods>
      <numMethodsExecuted>1580</numMethodsExecuted>
      <numMethodsNotExecuted>668</numMethodsNotExecuted>
    </coverageData>
    <image>
      <name short="a.exe" long="c:\a.exe" />
      <coverageData>
        <pctLinesExecuted>64.5435</pctLinesExecuted>
        <numLines>24633</numLines>
        <numLinesExecuted>15899</numLinesExecuted>
        <numLinesNotExecuted>8734</numLinesNotExecuted>
        <pctMethodsExecuted>70.8492</pctMethodsExecuted>
        <numMethods>2096</numMethods>
        <numMethodsExecuted>1485</numMethodsExecuted>
        <numMethodsNotExecuted>-1485</numMethodsNotExecuted>
      </coverageData>
      <sourceFile>
        <path>a.c</path>
        <filename>sim_efs.c</filename>
        <coverageData>
          <pctLinesExecuted>68.6885</pctLinesExecuted>
          <numLines>1220</numLines>
          <numLinesExecuted>838</numLinesExecuted>
          <numLinesNotExecuted>382</numLinesNotExecuted>
          <pctMethodsExecuted>93.4426</pctMethodsExecuted>
          <numMethods>61</numMethods>
          <numMethodsExecuted>57</numMethodsExecuted>
          <numMethodsNotExecuted>4</numMethodsNotExecuted>
        </coverageData>
        <executableLine>2</executableLine>
        <executableLine>3</executableLine>
        <executableLine>4</executableLine>
        <function>
          <name>main</name>
          <image>a.exe</image>
          <address>0x000103c0</address>
          <coverageData>
            <called>5</called>
            <sourceFile>a.c</sourceFile>
            <linesExecuted>2</linesExecuted>
            <linesNotExecuted>1</linesNotExecuted>
            <totalLines>3</totalLines>
            <pctCovered>66.67</pctCovered>
            <state />
          </coverageData>
          <sourceLineData>
            <line number="2" executionCount="5" />
            <line number="3" executionCount="0" />
            <line number="4" executionCount="0" />
            <line number="5" executionCount="5" />
          </sourceLineData>
        </function>
      </sourceFile>
    </image>
  </images>
</sessionFile>
]]

function qt.tests.xml()
   local cov = Cov.new()

   assert(cov:loadDPXML(xmlInput))

   local dat = cov:getFileTable("a.c","dat")

   eq(nil, dat[1])
   eq(5, dat[2])
   eq(0, dat[3])
   eq(0, dat[4])
   eq(5, dat[5])
   eq(nil, dat[6])

   print("cov ok")
end


function qt.tests.fileMatches()
   local function fm(...) return Cov.fileMatches(...) end

   assert(fm("foo.c", "foo.c"))
   assert(fm("foo.c", "Foo.c"))
   assert(fm("foo.c", "/a/b/Foo.c"))
   assert(fm("Foo.c", "/a/b/foo.c"))
   assert(not fm("foo.c", "afoo.c"))
   assert(not fm("afoo.c", "/a/b/foo.c"))
   assert(not fm("/foo.c", "/a/b/foo.c"))
   assert(not fm("a/foo.c", "/a/b/foo.c"))
   assert(fm("b/foo.c", "/a/b/foo.c"))
   assert(fm("b/foo.c", "/a/b/foo.c"))
   assert(fm("/a/b/foo.c", "/a/b/foo.c"))
end


local becInput1 = [[
#csv file,pctFunctCalled,functNotCov,pctCondCov,condNotCov,bec
a,100,0,100,0,::n:t:f:y::Ttfy::Ffty::N:T:F:Y::x:o
b,100,0,100,0,::n:t:f:y::Ttfy::Ffty::N:T:F:Y::x:o

]]

local becInput2 = [[
#csv file,pctFunctCalled,functNotCov,pctCondCov,condNotCov,bec
a,100,0,100,0,::y:f:t:y::Ffty::Ttfy::Y:F:T:Y::o:x

]]


local function getEvents(cov, src)
   return table.concat(cov:getFileTable(src, "bdat"), ":")
end

function qt.tests.bec()
   local cov = Cov.new()
   local bdat

   cov:loadText(becInput1)

   eq( "::n:t:f:y::Ttfy::Ffty::N:T:F:Y::x:o", getEvents(cov, "a"))
   eq( "::n:t:f:y::Ttfy::Ffty::N:T:F:Y::x:o", getEvents(cov, "b"))

   cov:loadText(becInput2)
   bdat = cov:getFileTable("a","bdat")

   eq( "::y:y:y:y::Yyyy::Yyyy::Y:Y:Y:Y::x:x", getEvents(cov, "a"))
   eq( "::n:t:f:y::Ttfy::Ffty::N:T:F:Y::x:o", getEvents(cov, "b"))
end

local bullseyeInput1 = [[
"Source","Line","Letter","Kind","Event","Function"
"a",3,"a","decision","T",""
"a",3,"b","condition","t",""
"a",9,"","decision","",""
"a",10,"","switch-label","",""
"a",11,"","switch-label","",""
"b",6,"","function","",""
"c",4,"a","decision","TF","test"
"c",4,"b","condition","t","test"
]]

local bullseyeInput2 = [[
"Source","Line","Letter","Kind","Event","Function"
"a",3,"a","decision","F",""
"a",3,"b","condition","f",""
"a",9,"","decision","TF",""
"a",10,"","switch-label","",""
"a",11,"","switch-label","X",""
"b",6,"","function","X",""
"c",4,"a","decision","TF","test"
"c",4,"b","condition","f","test"
]]

function qt.tests.bullseye()
   local cov = Cov.new()
   local bdat

   cov:loadText(bullseyeInput1)
   eq( "::Tt::::::N:s:s", getEvents(cov, "a"))
   eq( ":::::o", getEvents(cov, "b"))
   eq( ":::Yt", getEvents(cov, "c"))


   cov:loadText(bullseyeInput2)
   eq( "::Yy::::::Y:s:S", getEvents(cov, "a"))
   eq( ":::::x", getEvents(cov, "b"))
   eq( ":::Yy", getEvents(cov, "c"))
end

local becInput3 = [[
#csv file,linesExecutable,linesExecuted,pctExecuted,functTotal,functCov,condTotal,condCov,lct,bec
a,,,,0,0,6,2,,::Tt::::::N:s:S
c,,,,0,0,4,3,,:::Yt
b,,,,1,0,0,0,,:::::o

]]

function qt.tests.bullseye_and_bec()
   local cov = Cov.new()
   local bdat

   cov:loadText(bullseyeInput2)
   cov:loadText(becInput3)

   eq( "::Yy::::::Y:s:S", getEvents(cov, "a"))
   eq( ":::::x", getEvents(cov, "b"))
   eq( ":::Yy", getEvents(cov, "c"))
end

function qt.tests.bullseye_logic()
   local function merge(a,b)
      return Cov.bullseyeMergeTbl[a..b]
   end

   local function bOr (a, b)
      -- Break a and b into bits
      local a0, a1, b0, b1 = (a%2 == 1), a >= 2, (b%2 == 1), b >= 2
      --Recombine bits and return
      return ((a1 or b1) and 2 or 0) + ((a0 or b0) and 1 or 0)
   end

   local cov = Cov.new()
   local c_events = {"n","t","f","y"}
   local d_events = {"N","T","F","Y"}
   local f_events = {"o","x"}
   local s_events = {"s","S"}

	-- Test condition/decision merging
   for a=1,4 do
      for b=1,4 do
         eq(c_events[bOr(a-1,b-1)+1], merge(c_events[a], c_events[b]))
         eq(d_events[bOr(a-1,b-1)+1], merge(d_events[a], d_events[b]))
      end
   end

	-- Test function/switch merging
   for a=1,2 do
      for b=1,2 do
         eq(f_events[bOr(a-1,b-1)+1], merge(f_events[a], f_events[b]))
         eq(s_events[bOr(a-1,b-1)+1], merge(s_events[a], s_events[b]))
      end
   end
end

return qt.runTests(...)
