-- httpd.lua
--
-- Usage:
--
--    local HTTPD = require "httpd"
--    local server = HTTPD:new(addr, handler)
--    server:start()
--    server:stop()
--

local Object = require "object"
local xpio = require "xpio"
local xuri = require "xuri"
local thread = require "thread"
local SubStream = require "substream"
local lpeg = require "lpeg"

local pairs, ipairs, rawset, tonumber, tostring, assert, type =
   pairs, ipairs, rawset, tonumber, tostring, assert, type

local insert, remove, concat = table.insert, table.remove, table.concat

local bLog = os.getenv("httpd_log") == "1"


-- uriSplit(uri) --> prefix, path, query
--
-- Split a URI presented by the client. If "scheme://authority" precedes
-- the path, that is extracted as prefix.  If a "?" appears in that path,
-- that is extracted as `query`.
--
local function uriSplit(uri)
   local prefix
   if not uri then
      return
   elseif not uri:match("^/") then
      prefix, uri = uri:match("([^/:]+://[^/]*)(/?.*)")
      if uri == "" then
         uri = "/"
      elseif not uri then
         return
      end
   end

   return prefix, uri:match("([^%?]*)(.*)")
end


local charEscape = {}
charEscape["\n"] = "\\n\n"
charEscape["\r"] = "\\r"
charEscape["\\"] = "\\\\"
setmetatable(charEscape, { __index = function (t,ch) return ("\\%03d"):format(ch:byte()) end })


local function log(who, data)
   if bLog then
      local enc = data:gsub("[%z\1-\31\128-\255\\]", charEscape)
      print(who .. ": " .. enc:gsub("\n(.)", "\n : %1"))
   end
end


local function flatten(v)
   if v == nil then
      return ""
   end
   local t = {}
   local n = 0
   local err

   local function f(v)
      if type(v) == "string" then
         n = n + 1
         t[n] = v
      elseif type(v) == "table" then
         for _, e in ipairs(v) do
            f(e)
         end
      else
         err = "Invalid value in response.body: type = " .. type(v)
      end
   end

   f(v)
   return concat(t), err
end


local function clone(old)
   local new = {}
   for k, v in pairs(old) do
      new[k] = v
   end
   return new
end


-- Strict patterns for HTTP "token" [3.2]

local patToken = "[^\0-\32\127()<>@,;:\\\"/[%]%?={}]+"
-- local TOK = R("!!", "#'", "*+", "-.", "09", "AZ", "^z", "||", "~~")^1

local function parseList(str)
   local t = {}
   for tok in (str or ""):gmatch(patToken) do
      t[#t+1] = tok
      t[tok] = #t
   end
   return t
end


-- encode one chunk
local function chunkEncode(str)
   return string.format("%X", #str) .. "\r\n" .. str .. "\r\n"
end


local parseTE
do
   local P, R, S, C, Cs, Ct = lpeg.P, lpeg.R, lpeg.S, lpeg.C, lpeg.Cs, lpeg.Ct

   local lws   = R'\1\32'^0
   local function T(pat)
      return pat * lws
   end

   local function makeTE(name, tbl)
      tbl.name = name
      return tbl
   end

   local TOK   = C((R'!~' - S',;="')^1) * lws
   local QSTR  = P'"' * Cs( ((1 - S'"\\') + (P'\\'/'' * 1))^0) * P'"' * lws
   local PARAM = TOK * T'=' * (TOK + QSTR) / function (a,b) return a.."="..b end
   local TE    = TOK * Ct( (T';' * PARAM)^0 ) / makeTE
   local TC    = lws * Ct(TE * (T',' * TE)^0 + P(true))

   function parseTE(str)
      return TC:match(str)
   end
end


------------------------------------------------------------------------
-- cacheTable: cache results of a string->string translation function
------------------------------------------------------------------------

-- limits mitigate DoS
local cacheLimit = 10000
local keyLimit = 40

local function cacheTable(f)
   local room = cacheLimit
   local function index(t, k)
      local v = f(k)

      if #k <= keyLimit then
         room = room - #k
         if room < 0 then
            -- dump entire cache
            for k, v in pairs(t) do
               rawset(t, k, nil)
            end
            room = cacheLimit - #k
         end
         rawset(t, k, v)
      end
      return v
   end
   return setmetatable({}, {__index=index, __call=index})
end

local function headerInFunc(k)
   return ( k:lower():gsub("%-([a-z])", string.upper) )
end

local function headerOutFunc(k)
   return ( k:gsub("[A-Z]", "-%1"):gsub("^[a-z]", string.upper) )
end

local headerIn = cacheTable(headerInFunc)
local headerOut = cacheTable(headerOutFunc)


----------------------------------------------------------------
-- PH : Parse HTTP Request
----------------------------------------------------------------
--
-- Synopsis:
--
--   ph = HTTPD:new()   -- or ph:restart()
--   repeat
--      ph:takeData(...)
--   until ph:isDone()
--   if not ph.error then
--      ph.version  --> HTTP 1.x minor version, or -1 for HTTP 0.9
--      ph.method   --> method
--      ph.uri      --> URI
--      ph.headers  --> as defined in httpd.txt
--   else
--      ph.error    --> "bad" (malformed) | "unsupported" (HTTP 2+)
--   end


-- HTTP version --> major, minor
local patVersion = "HTTP/(%d+)%.(%d+)"

-- request line --> method, uri, major, minor   [matches complete string]
local patRequest = "^(" .. patToken .. ") ([^ ]+) " .. patVersion .. " *\r?\n"


local PH = Object:new()

local pstSTART = 1
local pstHDRS = 2
local pstDONE = 3


function PH:initialize()
   self:restart()
end

function PH:restart()
   self.state = pstSTART
   self.data = ""
   self.version = -1
   self.headers = {}
   self.lastHeader = false
end


function PH:isDone()
   return self.state == pstDONE
end


function PH:takeData(newData)
   local st = self.state
   local data = self.data .. newData
   local nextLine = 1
   local hdrs = self.headers

   while st ~= pstDONE do
      local lineEnd = data:find("\n", nextLine)
      if not lineEnd then break end

      local thisLine = nextLine
      nextLine = lineEnd + 1

      if st == pstSTART then
         -- parse first line

         -- try HTTP/1.0+ (explicit version number)
         local m, u, a, b = data:match(patRequest, thisLine)

         if not m then
            -- try HTTP/0.9 (no version)
            m, u = data:match("^([^ \t]+) +(/[^ \t\r\n]*)\r?\n", thisLine)
            if m then
               self.method = m
               self.uri = u
            else
               self.error = "bad"
            end
            st = pstDONE
         elseif a ~= "1" then
            self.error = "unsupported"
            st = pstDONE
         else
            self.method = m
            self.uri = u
            self.version = tonumber(b)
            st = pstHDRS
         end

      elseif st == pstHDRS then
         -- parse header line

         local name, value = data:match("^([^\0-\32:]+)[ \t]*:[ \t]*([^\r\n]*)\r?\n", thisLine)
         if name then
            -- name ":" value
            name = headerIn[name]
            if hdrs[name] then
               value = hdrs[name] .. "; " .. value
            end
            hdrs[name] = value
            self.lastHeader = name
         elseif data:match("^\r?\n", thisLine) then
            -- empty line
            st = pstDONE
            break
         else
            -- continuation line
            local cont = data:match("^[ \t]*([^\r\n]*)", thisLine)
            if cont and self.lastHeader then
               hdrs[self.lastHeader] = hdrs[self.lastHeader] .. " " .. cont
            else
               self.error = "bad"
               st = pstDONE
            end
         end
      end
   end

   self.data = data:sub(nextLine)  -- preserve un-consumed data
   self.state = st
end


----------------------------------------------------------------
-- Status codes
----------------------------------------------------------------

local httpStatusCodes = {
   [100] = "Continue",
   [101] = "Switching Protocols",
   [200] = "OK",
   [201] = "Created",
   [202] = "Accepted",
   [203] = "Non-Authoritative Information",
   [204] = "No Content",
   [205] = "Reset Content",
   [206] = "Partial Content",
   [300] = "Multiple Choices",
   [301] = "Moved Permanently",
   [302] = "Found",
   [303] = "See Other",
   [304] = "Not Modified",
   [305] = "Use Proxy",
   [306] = "(Unused)",
   [307] = "Temporary Redirect",
   [400] = "Bad Request",
   [401] = "Unauthorized",
   [402] = "Payment Required",
   [403] = "Forbidden",
   [404] = "Not Found",
   [405] = "Method Not Allowed",
   [406] = "Not Acceptable",
   [407] = "Proxy Authentication Required",
   [408] = "Request Timeout",
   [409] = "Conflict",
   [410] = "Gone",
   [411] = "Length Required",
   [412] = "Precondition Failed",
   [413] = "Request Entity Too Large",
   [414] = "Request-URI Too Long",
   [415] = "Unsupported Media Type",
   [416] = "Requested Range Not Satisfiable",
   [417] = "Expectation Failed",
   [500] = "Internal Server Error",
   [501] = "Not Implemented",
   [502] = "Bad Gateway",
   [503] = "Service Unavailable",
   [504] = "Gateway Timeout",
   [505] = "HTTP Version Not Supported",
}


----------------------------------------------------------------
-- WDConn: Web Daemon connection
----------------------------------------------------------------

local BUFSIZE = 1024

local WDConn = Object:new()

local cstINIT    = 1
local cstREQUEST = 2
local cstHANDLER = 3
local cstDISCARD = 4
local cstRESPOND = 5


function WDConn:initialize(socket, handler, httpd)
   self.socket = socket
   self.handler = handler
   self.data = ""
   self.ph = PH:new()
   self.httpd = httpd
   self.thread = thread.new(self.run, self)
   self.server = httpd.name
   self.context = {
      client = socket:getpeername()
   }
end


function WDConn:shutDown(timeout)
   -- TODO: let pending transactions finish (in up to `timeout` seconds)
   self:dtor()
end


function WDConn:dtor()
   if not self.inDtor then
      self.inDtor = true
      if self.thread then
         -- this might re-entre dtor (due to atExit function)
         thread.kill(self.thread)
      end
      self.socket:close()
      self.httpd:removeConn(self)
   end
end


function WDConn:warn(...)
   print("httpd.lua warning: " .. string.format(...))
end


-- Handle request
--
-- On exit:
--    self.subStream = nil | readStream
--    self.connClose = true => close conn to terminate response
--
-- If `subStream` is non-nil, it contains a read stream, which may
-- have been partially or completely consumed by the handler, and it
-- may continue to be consumed when respond() is executed.
--
function WDConn:handle()
   local prefix, path, query = uriSplit(self.ph.uri)
   if not path or self.ph.error then
      self.connClose = true
      return 505, {}, ""
   end

   local headers = self.ph.headers
   local len = tonumber(headers.contentLength)

   local connHdr = parseList( (headers.connection or ""):lower() )
   self.connClose = connHdr.close
      or self.ph.version < 1 and not connHdr.keepAlive

   -- Message body [see 4.4]
   local teUsed = headers.transferEncoding
   if teUsed then
      local tencs = parseTE(teUsed)
      if tencs[1] and tencs[1].name ~= "identity" then
         -- request transfer-encoding not supported => cannot determine
         -- request body length => abandon transaction and socket
         self.connClose = true
         return 501, {}, ""
      end
   end

   local extra = self.ph.data
   self.ph.data = ""
   self.subStream = SubStream:new(self.socket, extra, len or 0)

   local request = {
      method = self.ph.method,
      server = self.server,
      root = "",
      path = path,
      query = query,
      headers = headers,
      body = self.subStream,
      context = self.context
   }

   -- handler(request) --> status, headers, body
   return self.handler(request)
end

-- Returns: nil | error
--
function WDConn:respond(code, headers, body)
   local status      -- status description
   local bodyBytes   -- body as a string
   local bodyFunc    -- body as a streaming function
   local chunked     -- true IFF body is chunked

   -- status code & text

   status = httpStatusCodes[code]
   if not status then
      code = 500
      status = httpStatusCodes[code]
   end

   -- body

   -- See RFC 2616 4.4
   if code == 204
      or code == 304
      or code <= 199
      or self.ph.method == "HEAD"
   then
      -- No body to be sent (per spec)
   elseif type(body) == "function" then
      if self.ph.version < 1 then
         self.connClose = true
      elseif not self.connClose then
         chunked = true
      end
      bodyFunc = body
   else
      local err
      bodyBytes, err = flatten(body)
      if err then
         self:warn(err)
      end
   end

   -- normalize headers

   if type(headers) ~= "table" then
      self:warn("headers is not a table")
      headers = {}
   else
      headers = clone(headers)
   end

   if self.connClose then
      headers.connection = "Close"
   elseif chunked then
      headers.transferEncoding = "chunked"
      headers.contentLength = nil
   end

   if bodyBytes and not headers.contentLength then
      headers.contentLength = tostring(#bodyBytes)
   end

   -- construct response

   local responseLines = {
      "HTTP/1.1 " .. code .. " " .. status
   }
   for k, v in pairs(headers) do
      insert(responseLines, headerOut[k] .. ": " .. v)
   end
   insert(responseLines, "")
   insert(responseLines, bodyBytes or "")

   local response = concat(responseLines, "\r\n")

   log("S", response)
   local _, responseError = self.socket:write(response)

   if bodyFunc then

      local function emit(data)
         if responseError then
            return nil, responseError
         end
         data = flatten(data)
         if data == "" then
            return true
         end

         if chunked then
            data = chunkEncode(data)
         end
         log("S", data)
         local _, err = self.socket:write(data)
         if err then
            responseError = err
            return nil, responseError
         end
         return true
      end

      bodyFunc(emit)
      if chunked and not responseError then
         -- last chunk, (empty) trailer, and final CRLF
         log("S", "0\r\n")
         self.socket:write("0\r\n\r\n")
      end
   end

   return responseError
end



function WDConn:run()
   thread.atExit(self.dtor, self)

   while true do

      while not self.ph:isDone() do
         local data, err = self.socket:read(BUFSIZE)
         if data then
            log("C", data)
            self.ph:takeData(data)
         elseif err then
            -- read error: abandon connection
            log("C", "<error: " .. tostring(err) .. ">")
            return
         elseif self.ph.data ~= "" then
            -- close after partial request
            log("C", "<close after partial request>")
            return
         else
            -- no requests bytes => graceful close (common after first
            -- request/response, but there is no reason to complain if we
            -- get an immediate EOF at the start)
            log("C", "<close>")
            return
         end
      end

      local code, headers, body = self:handle()

      -- respond
      local err = self:respond(code, headers, body)
      if err then
         log("S", "<error: " .. tostring(err) .. ">")
         return
      end

      if self.connClose then
         -- close connection
         return
      end

      local leftovers

      -- read and discard the request body (if not already consumed)
      if self.subStream then
         local err = self.subStream:drain()
         if err then
            -- error in stream
            log("C", "<error: " .. tostring(err) .. ">")
            return
         end

         -- collect any remaining read-ahead
         leftovers = self.subStream:leftovers()
         self.subStream = nil
      else
         leftovers = self.ph.data
      end

      self.ph:restart()
      self.ph:takeData(leftovers)
   end
end


----------------------------------------------------------------
-- HTTPD: listen + accept loop
----------------------------------------------------------------

local HTTPD = Object:new()

function HTTPD:initialize(addr)
   self.addr = addr
   self.name = "http://" .. addr:gsub("^:", "127.0.0.1:")
   self.conns = {}
   self.sock = xpio.socket("TCP")
end


function HTTPD:serve()
   while true do
      local s, err = self.sock:accept()
      if s then
         local conn = WDConn:new(s, self.handler, self)
         insert(self.conns, conn)
      elseif err ~= "retry" then
         error(err)
      end
   end
end


function HTTPD:start(handler)
   self.handler = handler
   assert( self.sock:setsockopt("SO_REUSEADDR", true) )
   assert( self.sock:bind(self.addr) )
   assert( self.sock:listen() )

   self.thread = thread.new(self.serve, self)
end


function HTTPD:removeConn(conn)
   for n = 1, #self.conns do
      if self.conns[n] == conn then
         remove(self.conns, n)
         return
      end
   end
end


function HTTPD:getAddr()
   return self.sock:getsockname()
end


-- Stop the accepting thread, and optionally kill all pending connection threads
--
function HTTPD:shutDown(timeout)
   thread.kill(self.thread)
   for _, conn in ipairs(self.conns) do
      conn:shutDown(timeout)
   end
end


function HTTPD:stop()
   self:shutDown(0)
end


HTTPD.headerIn = headerIn
HTTPD.headerOut = headerOut


-- export for unit test
HTTPD.PH = PH
HTTPD.parseTE = parseTE


return HTTPD
