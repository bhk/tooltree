----------------------------------------------------------------
-- Test HTTP request parser
----------------------------------------------------------------
--
-- Test cases are prefixed by comments in the following format:
--
--   >> ASSERTION
--

local qt = require "qtest"
local HTTPD = require "httpd"
local memoize = require "memoize"
local xpio = require "xpio"
local thread = require "thread"
local BufIO = require "bufio"

local eq = qt.eq

local function lessThan(a, b)
   if a >= b then
      qt.error( string.format("Expected %s < %s", a, b), 2)
   end
end



--------------------------------
-- Test parsing of transfer-coding
--------------------------------

local parseTE = HTTPD.parseTE

--eq("name", TOK:match("name = vvv \t"))
--eq("name=vvv", PARAM:match("name = vvv \t"))
--eq("abc", QSTR:match('"abc"'))
--eq([[name= a "\ =;]], PARAM:match([[name = " a \"\\ =;" \t]]))
eq({
      {name="foo", "A=1", "B=2"},
      {name="bar"}
   },
   parseTE("foo ; A = 1 ;B = 2, bar"))


--------------------------------
-- headerIn/Out
--------------------------------

local hi, ho = HTTPD.headerIn, HTTPD.headerOut

eq('ifNoneMatch', hi 'If-None-matCh' )
eq('a', hi('A'))
eq('-A-', hi('--A-'))

eq('Content-Type', ho 'contentType' )
eq('--A-', ho('-A-'))
eq('-A-Bc-D', ho 'ABcD' )


-- headerIn/headerOut limit memory usage

local longString = ("a"):rep(33) -- under the keyLimit threshold
for n = 1, 300 do
   local s = longString .. n
   ho(s)
   hi(s)
end

local function getCacheSize(c)
   local tot = 0
   for k, v in pairs(c) do
      tot = tot + #k
   end
   return tot
end

lessThan(getCacheSize(hi), 10001)
lessThan(getCacheSize(ho), 10001)

--------------------------------
-- Test HTTP parser
--------------------------------

local PH = HTTPD.PH


local tvec = {
   {
      "GET /p/q\r\n",
      uri = "/p/q",
      headers = {},
      method = "GET",
      version = -1,
      data = "",
   },
   {
      "GET /b HTTP/1.1\nb1: x\nb2: y \n\r\n\nxy",
      bodyLen = 3,
      uri = "/b",
      headers = {b1="x", b2="y "},
      method = "GET",
      version = 1,
      data = "\nxy",
   },

   -- continuation lines
   {
      "GET /c HTTP/1.1\nc1: a\r\n\tb\r\n :c\r\nc2: b\nc1: z\r\n\r\nCC",
      bodyLen = 3,
      uri = "/c",
      headers = {c1="a b :c; z", c2="b"},
      method = "GET",
      version = 1,
      data = "CC",
   },
   {
      "GET /b HTTP/2.1\nb1: x\nb2: y \n\r\n\n",
      earlyError = true,
      error = "unsupported"
   },
   {
      "xyz\n",
      error = "bad",
   }
}


for n, test in ipairs(tvec) do
   local data = test[1]

   -- parse request in one or two chunks: [1...split] [split+1...]

   for split = 0, #data - (test.bodyLen or 0) - 1 do
      local ph = PH:new()

      local a = data:sub(1, split)
      local b = data:sub(split + 1)

      -- parse first half
      if test.earlyError then
         ph:takeData(a)  -- may succeed or fail by now
      elseif split > 0 then
         ph:takeData(a)
         eq(ph:isDone(), false)
         ph:takeData("")
         eq(ph:isDone(), false)
      end
      ph:takeData(b)
      eq(ph:isDone(), true)

      if test.error then
         eq(ph.error, test.error)
      else
         eq(ph.method, test.method)
         eq(ph.version, test.version)
         eq(ph.uri, test.uri)
         eq(ph.headers, test.headers)
         eq(ph.data, test.data)
      end
   end
end


--------------------------------
-- Test HTTPD with connections
--------------------------------


-- 'show' handler echoes request information
local function testHandler(request)
   local body = {}
   local function o(str)
      table.insert(body, str)
   end

   if request.path == "/empty" then

      -- nothing

   elseif request.path == "/request" then

      body = table.concat {
         "server=" .. request.server .. ";",
         "root=" .. request.root .. ";",
         "path=" .. request.path .. ";",
         "context.client=" .. request.context.client .. ";"
      }

   elseif request.path == "/hello" then

      body = "Hello!"

   elseif request.path == "/headers" then

      for name, value in pairs(request.headers) do
         o( name .. " = " .. value .. "\n" )
      end

   elseif request.path == "/echo" then

      -- read and echo payload
      local s = request.body
      while true do
         local data, err = s:read(4096)
         if data then
            o(data)
         elseif err then
            error("testHandler: " .. err)
         else
            return 200, {contentType = "text/plain"}, body
         end
      end

   elseif request.path == "/stream" then

      -- streaming response; no content-length
      local function strm(emit)
         emit "Hello "
         emit ""           -- should not be a problem
         emit "World!"
      end

      local hdrs = {
         contentType = "text/plain",
         contentLength = "12"
      }

      return 200, hdrs, strm

   elseif request.path == "/streamEcho" then

      local function strm(emit)
         while true do
            local data = request.body:read(4096)
            if not data then return end
            emit(data)
         end
      end

      return 200, {ccontentType = "text/plain"}, strm

   else
      body = "Unexpected path: '" .. tostring(request.path) .. "'"
   end

   return 200, {contentType = "text/plain"}, body
end


----------------------------------------------------------------
-- Chunked body reading
----------------------------------------------------------------

-- read one chunk
--
local function readChunk(s)
   local sz = assert(s:read('*l'))
   sz = qt.match(sz, "^(%x+)")

   local size = tonumber(sz, 16)
   if size == 0 then
      return nil
   end
   local data, err = s:read('=', size + 2)
   qt.match(data, "\r\n$")
   return data:sub(1, -3)
end


-- Read chunk trailer section
--
local function readTrailer(s)
   local headers = {}

   while true do
      local line = assert(s:read('*l'))
      if line == "" then
         return headers
      else
         table.insert(headers, line)
      end
   end
end


-- Read chunked body (data + trailers)
-- Returns: body, trailers
local function readChunkedBody(s)
   local body = ""

   while true do
      local chunk, err = readChunk(s)
      if err then
         return nil, err
      elseif not chunk then
         return body, readTrailer(s)
      end
      body = body .. chunk
   end
end


-- consume the status line
local function readStatus(s)
   local line = assert(s:read('*l'))
   local code = qt.match(line, "^HTTP/1.1 (%d%d%d) ")
   return tonumber(code)
end


-- consume headers, up to and including the blank line
local function readHeaders(s)
   local headers = {}
   while true do
      local line = s:read('*l')
      if line == "" then return headers end
      local name, value = qt.match(line, "^([^ :]+) *: *(.*)")
      headers[name:lower():gsub("%-([a-z])", string.upper)] = value
   end
end


local function makeRequest(req)
   local t = {}
   local function o(line)
      table.insert(t,line)
   end

   local ver = req.ver or "1.1"

   o( (req.method or "GET") .. " " .. req.uri .. " HTTP/" .. ver )
   for _, h in ipairs(req) do
      o(h)
   end
   if req.body then
      o("Content-Length: " .. #req.body)
   end
   o("")
   o(req.body or "")
   return table.concat(t, "\r\n")
end


local function testServer()
   local qt = require "qtest"
   local d = HTTPD:new("127.0.0.1")

   d:start(testHandler)

   local rawSocket, s, connLive

   local function connect(bDebug)
      if s then
         s:close()
      end
      rawSocket = xpio.socket("TCP")
      assert(rawSocket:connect(d:getAddr()))
      s = BufIO:new(rawSocket)
      if bDebug then
         qt.trace("read(_,%s)", s)
      end
      connLive = true
   end

   local function request(req)
      if not connLive then
         error("Connection closed; use `connect`", 2)
      end
      return s:write( makeRequest(req) )
   end

   local st, headers, buf, len, body, trailers

   local function expect(statusExpected, bodyExpected)
      st = readStatus(s)
      qt._eq(st, statusExpected, 2)
      headers = readHeaders(s)

      local serverClose = (headers.connection or ""):lower() == "close"
      if serverClose then
         connLive = false
      end

      if bodyExpected == false then
         -- no body expected; ignore Content-Length, etc.
         body = nil
         return
      end

      -- this function only handle content-length-delimited responses
      len = tonumber(headers.contentLength)
      local tenc = headers.transferEncoding
      trailers = nil

      if serverClose then
         body = s:read('*a') or ""
      elseif tenc then
         eq(tenc:lower(), "chunked")
         eq(nil, len)
         body, trailers = readChunkedBody(s)
      elseif len then
         body = s:read('=', len)
      else
         qt.error("Expected content-length or 'connection: close'")
      end

      if bodyExpected then
         qt._eq(bodyExpected, body, 2)
      end
   end

   -- larger than the BUFSIZE
   local LARGE = ("0123456789"):rep(5000)

   -- >> Old-style ("0.9") request

   connect()
   s:write("GET /hello\r\n")
   expect(200, "Hello!")

   -- >> server closes connection in case of HTTP/1.0 request

   connect()
   request{ uri="/empty", ver="1.0" }
   expect(200, "")
   buf = s:read(100)
   eq(buf, nil)  -- expected empty response

   -- >> server closes connection in case of "Connection: close"

   connect()
   request{ uri="/hello", ver="1.0", "Connection: Close" }
   expect(200, "Hello!")
   eq("Close", headers.connection)

   -- >> Server does not close connection with 1.1 clients
   -- >> Server sends content-length (generated by httpd, not by handler)

   connect()
   s:write("GET /hello HTTP/1.1\r\n\r\n")
   expect(200, "Hello!")
   eq(nil, headers.connection)

   -- >> second transaction on the same socket
   -- >> non-empty repsonse bodies are handled properly
   -- >> headers are properly decoded and presented to app

   -- reuse connection
   request{ uri="/headers", "Host: localhost" }
   expect(200, "host = localhost\n")

   -- >> request.body can be used to read the request body

   -- (require "trace").on{"httpd.lua", "httpd_q.lua", "substream"}
   request{ uri="/echo", method="POST", body="Payload" }
   expect(200, "Payload")

   -- >> request.const is provided.

   request{ uri="/request" }
   expect(200)
   local t = {}
   for name, value in body:gmatch("(.-)=(.-);") do
      t[name] = value
   end
   qt.match(t.server, "http://")
   eq(t.root, "")
   eq(t.path, "/request")
   eq(t['context.client'], rawSocket:getsockname())

   -- >> If request body is not consumed by handler, HTTPD will
   --    skip the unread request bytes.

   request{ uri="/hello", method="POST", body=LARGE }
   expect(200, "Hello!")
   request{ uri="/hello" }
   expect(200, "Hello!")

   -- >> server pipelines more than one request AND OFFERS HTTP/1.0
   --    (ApacheBench bug)

   local bogus10 = ("GET /empty HTTP/1.0\r\nHost: 127.0.0.1:8888\r\n\r\n"):rep(10)
   local cnt = s:write(bogus10)
   expect(200, "")
   eq(headers.connection, "Close")

   -- >> [3.6] Streaming response, no content-length, 1.0 client => payload
   --    delivered using "connection: close".

   connect()
   request{ ver="1.0", uri="/stream" }
   expect(200, "Hello World!")
   eq(headers.connection, "Close")

   -- >> Streaming response, 1.1 client => payload delivered using
   --    "transfer-encoding: chunked".
   -- >> Content-Length is not sent with chunked encoding, even if handler
   --    provides content-length.

   connect()
   request{ uri="/stream" }
   expect(200, "Hello World!")
   eq(nil, headers.connection)
   eq(nil, headers.contentLength)
   eq("chunked", headers.transferEncoding)
   eq(trailers, {})

   -- >> A streaming response body may consume data from the request body.
   --    [Make sure it is longer than the buffered amount.]

   request{ uri="/streamEcho", method="POST", body=LARGE }
   expect(200, LARGE)

   -- >> [3.6] Should return 501 in response to unsupported transfer-coding.

   connect()
   request{ uri="/stream", "Transfer-EnCoDing: rot13" }
   expect(501, "")
   eq(headers.connection, "Close")

   -- >> Unrecognized major version => reject connection.

   connect()
   request{ uri="/empty", ver="2.0" }
   expect(505, "")

   -- >> HEAD request shall return no body.

   connect()
   request{ uri="/hello", method="HEAD" }
   expect(200, false)
   request{ uri="/hello", method="GET" }
   expect(200, "Hello!")

   s:close()
   d:stop()
end


----------------------------------
-- Requirements form HTTP/1.1 spec
----------------------------------

-- [3.6] MUST NOT send chunked codings to a 1.0 client

-- [3.6] SHOULD return 501 in response to unsupported transfer coding

-- [3.6.1] MUST understand Transfer-Coding: chunked

-- [3.6.1] MUST ignore `chunk-extension` extensions they don't understand

-- [4.1] SHOULD ignore blank lines before stat line

-- [4.2] Multiple occurrences of a single header treated as comma-separated

-- [4.3] SHOULD read and forward a message body with any request (as
--   indicated by Content-Length or Transfer-Encoding

-- [4.3] Response MUST NOT include a message body when request method ==
--   "HEAD" or status code = 1xx, 204, or 304

-- [4.4] Content-Length MUST NOT be sent if Transfer-Encoding is sent

-- [4.4] Content-Length MUST be ignored if sent with Transfer-Encoding

-- [4.4] NOTE: this server does not support multipart/mixed

-- [5.1.1] GET and HEAD MUST be supported by all "general-purpose" servers.

-- [5.1.2] MUST accept absolute URIs

-- [8.1.2.1] Server SHOULD send "Connection: close" *when* it chooses to
--    close the connection.

-- [8.2.3] Upon receiving an "Expect" request header with the "100-continue"
--    expectation or respond with a final satus code (without waiting on the
--    request body).

-- [14.18] Origin servers MUST include a Date header field in all responses,
--    except in these cases: (a) 100, 101, 5xx responses, or (b) if the
--    server does not have a clock that provides a reasonable approximation
--    of current time (in which case, it MUST NOT).

-- [14.20] A server that does not understand or is unable to comply with any
--    of the expectation values MUST response with appropriate error status.

-- [14.23] servers MUST respond with 400 to any HTTP/1.1 request message
--    that lacks a `host` header.

----------------------
-- Other features TODO
----------------------

-- * What about requests with "scheme://auth" on the request line?

-- * Buffer streamed output and flush based on timer (or "on-block")

-- * Enhance handler API to describe accurate URL reconstruction logic.

-- * Connection timeout

-- * Put limits on everything.

-- * WDConn:warn() should use logging object (not `print`) that could be (a)
--   directed to a separate file from status messages, (b) viewed via admin
--   console.  ...  HTTPD should provide diagnostic/log/debug APIs to monitor
--   number of active connections, traffic on those connections, etc.. One
--   client of these might be a web app (implemented using HTTPD).
--
--   Similarly, handlers should be given something like request.context.stderr.

local function testmain()
   local tt = thread.new(function () thread.sleep(5) ; error("Timeout!") end)
   testServer()
   thread.kill(tt)
end

thread.dispatch(testmain)
