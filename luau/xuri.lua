-- xuri: parse/generate URIs
-- #########################
--
-- Summary
--
--     `xuri.parse` and `xuri.gen` resolve and normalize URIs, generating
--     table or string representations of URIs, respectively.  Either
--     function will accept tables or strings as inputs.
--
--     Either function accepts a second optional parameter, which, if given
--     will be used as the base URI for resolving the first URI, which may be
--     a relative URI.
--
--     The table form of a URI contains fields corresponding to the
--     following components:
--
--     :  ,.......,    ,.........., ,..............,   ,....,   ,.....,
--     :  : http: :  //: x.com:80 : : /depot/users :  ?:x=on:  #: bin :
--     :  `...+...`    `....+.....` `......+.......`   `.+..`   `..+..`
--     :      :             :              :             :         :
--     :    scheme       authority        path         query    fragment
--
--     If a syntax element is not present in the URI, the corresponding
--     field in the table will be nil.
--
--     The query field is an exception.  Its contents are provided in a
--     table called `params`.  Each `&` or `;`-delimited query field is placed in
--     the params table.  For fields matching the form `<key>=<value>`,
--     params[<key>] is assigned to <value>.  Other fields are assigned
--     numeric indices, starting at 1.  Note that this may map URIs that are
--     distinct (according to the URI specification) to equivalent tables.
--
--     ;; When both `params` and `query` are present in a table passed to `gen`
--     ;; or `parse`, the query constructed from `params` takes precedence over
--     ;; the value in the `query` field.
--
--     Aside from `scheme` and `authority`, any strings that appear within
--     the table representation may contain arbitrary strings.  They will be
--     percent-encoded/decoded when a URI string is generated/parsed.
--     Scheme names may only contain the alphanumeric characters and "`+`",
--     "`-`" and "`.`" (as per the URI specification).  Authority is left in
--     its percent-encoded form so that it may be interpreted in a
--     scheme-specific manner.
--
--     These functions follow the relative URI processing and normalization
--     rules described in [RFC 3986] (http://tools.ietf.org/html/rfc3986),
--     except when combining relative URIs.  Unlike RFC 3986 The functions
--     defined herein preserve the property of associativity.  For example,
--     `gen(gen(r1, r2), base)` produces the same result as `gen(r1, gen(r2,
--     base))`.  This allows you to combine two relative URIs to generate a
--     new relative URI.
--
--     Strings returned by `gen` will have parameters ordered
--     deterministically, and no two parameters may have the same name.
--     Percent-encoding is made uniform.  This preserves the contents of the
--     `params` table but not all of the information in `query`.
--
--     Percent encoding is removed from all path characters.  This erases
--     the distinction between encoded and un-encoded characters (e.g. "/"
--     and "%2F").
--
-- xuri.parse(uri, [base])
--
--     Generate a normalized string representation of a URI.
--
-- xuri.gen(uri, [base])
--
--     Generate a normalized table representation of a URI.
--
--
-- Examples:
--
--    . xuri.parse("p?a;x=%3A%2F%3F")                 -->  {path="p", params={"a", x=":/?"}}
--    . xuri.gen{ params={"a", x=":/?"} }             -->  "?a;x=%3A%2F%3F"
--    . xuri.gen("?x=:/?&a")                          -->  "?a;x=%3A%2F%3F"
--    . xuri.gen("a", "http://host/base")             -->  "http://host/a"
--    . xuri.gen("a", "http://host/base/")            -->  "http://host/base/a"
--    . xuri.gen("a", "../")                          -->  "../a"
--    . xuri.gen("?x=1", "/a/pak")                    -->  "/a/pak?x=1"



local function hexToByte(s)
   return string.char(tonumber(s, 16))
end

local function byteToHex(ch)
   return string.format("%%%02X", string.byte(ch))
end

local function pctDecode(s)
   return ( s:gsub("%%(%x%x)", hexToByte) )
end


-- paramDecode / paramEncode: unescape/escape characters for embedding in a
-- URI query name or value.
--
-- We do not escape alphanumeric characters or RFC2396's "unreserved" except
-- that we *do* encode "'", which would vastly complicate shell quoting if
-- it were to appear un-escaped on a command line.  (This happens to match
-- the quoting in a Google search URI...)
--
-- RFC3986 unreserved :=  ALPHA / DIGIT / "-" / "." / "_" / "~"
--

local function paramDecode(s)
   return pctDecode(s:gsub("%+", " "))
end

local function paramEncode(s)
   return ( s:gsub("([^%w%!%(%)%*%-%._~ ])", byteToHex):gsub(" ","+") )
end


-- pathDecode / pathEncode: "/" and "+" appear unescaped (always);
--    spaces are encoded as %20.
--
local pathDecode = pctDecode

local function pathEncode(s)
   return ( s:gsub("([^%w%!%(%)%*%-%._~/%+])", byteToHex) )
end


-- hostDecode / hostEncode: ":" and "+" appear unescaped (always);
--    spaces are encoded as %20.
--
local authorityDecode = pctDecode

local function authorityEncode(s)
   return ( s:gsub("([^%w%!%(%)%*%-%._~:%+])", byteToHex) )
end


-- normlize & validate scheme: no encoding; just validation & string.lower
--

local function schemeNorm(s)
   if s:match("^[%w%+%-%.]+$") then
      return s:lower()
   end
   error("URI handling: Invalid scheme")
end


-- parseParams: parse name/value field of URL, returning { key=value, ...}
--
--   Values are always strings, URI-decoded.
--   Names are strings when a "=" appears in the field; otherwise, they
--      are numbers beginning with 1.
--   Example: "a=b;c=1;x"  -->  { a="b", c="1", "x" }
--
local function parseParams(str)
   local t = {}
   if str then
      for fld in str:gmatch("[^&;]+") do
         local k,v = fld:match("([^=]*)=(.*)")
         if k then
            t[paramDecode(k)] = paramDecode(v)
         elseif fld ~= "" then
            table.insert(t, paramDecode(fld))
         end
      end
   end
   return t
end


-- Construct URI query string from table.  This is the inverse of
-- parseParams.  In the generated string, fields are ordered
-- deterministically, so equivalent tables will generate identical results.
--
local function makeParams(t)
   if not t or not next(t) then
      return nil
   end

   local a = {}
   for n,v in ipairs(t) do
      if type(v) == "string" and v ~= "" then
         table.insert(a, paramEncode(v))
      end
   end

   local map = {}
   for k,v in pairs(t) do
      if type(k) == "string" and type(v) == "string" then
         table.insert(map, paramEncode(k).."="..paramEncode(tostring(v)))
      end
   end
   if map[1] then
      table.sort(map)
      table.insert(a, table.concat(map, ";"))
   end

   return table.concat(a, ";")
end


-- Produce a string form the table representation.  Any component except
-- path may be false or nil.
--
local function uriToString(t)
   if type(t) == "string" then return t end
   if type(t) ~= "table" then error("uri handling: Invalid type for URI: "..type(t)) end

   local query = t.params
   if type(query) == "table" then
      query = makeParams(query)
   end
   local path = t.path or ""

   return (t.scheme and schemeNorm(t.scheme)..":" or "")
       .. (t.authority and "//"..authorityEncode(t.authority) or "")
       .. ((t.authority and path:sub(1,1) ~= "/") and "/" or "")
       .. pathEncode(path)
       .. (t.version and "@"..paramEncode(t.version) or "")
       .. (query and "?"..query or "")
       .. (t.fragment and "#"..paramEncode(t.fragment) or "")
end


-- uriToTable: Parse package location and return elements.
--
-- Only 'path' is guaranteed to always be a string.  If scheme, authority, and
-- version are missing their values will be nil.
--
local function uriToTable(uri)
   if not uri then return {} end
   if type(uri) == "table" then return uri end
   if type(uri) ~= "string" then error("Invalid type for URI: "..type(uri)) end

   local s, h, p, v, q, u, f

   s, u = uri:match("^([%w%+%-%.]+)%:(.*)")
   uri = u or uri
   h, u = uri:match("^//([^/]*)(.*)")
   p, uri = (u or uri):match("^([^@%?#]*)(.*)")
   v, u = uri:match("@([^%?#]*)(.*)")
   uri = u or uri
   q, u = uri:match("^%?([^#]*)(.*)")
   uri = u or uri
   f = uri:match("^#(.*)")

   return {
      scheme = s,
      authority = h and authorityDecode(h),
      path = pathDecode(p),
      version = v and paramDecode(v),
      params = q and parseParams(q),
      fragment = f and paramDecode(f)
   }
end


local function dir(str, pos)
   while pos > 0 and str:sub(pos,pos) ~= "/" do
      pos = pos - 1
   end
   return str:sub(1,pos), pos
end


-- Clean a URI path:  remove redundant "." and ".." elements.
--
-- This differs from lfsu.cleanpath() because URIs identify directories
-- with trailing slashes.
--
-- Like RFC3986 it allows un-rooted paths (that do not begin with "/").
-- *Unlike* RFC3986 it preserves ".." elements at the start of the path (or
-- that end up at the start after processing other ".." elements).  As a
-- result, this code supports an associative definition of resolve():
--
--    resolve(r1, resolve(r2, base)) == resolve( resolve(r1, r2), base )
--
--       Input          Output     RFC3986 (if different)
--       "/dir/."       "/dir/"      --
--       "/dir/f/.."    "/dir/"      --
--       "/a/../b/f"    "/b/f"       --
--       "/.."          "/"          --
--       "/."           "/"          --
--       ".."           ".."         ""
--       "a/../.."      ".."         "/"
--       "."            "."          ""
--       "a/.."         ""           "/"
--       "../.."        "../.."      ""
--       "../a"         "../a"       "a"
--       "a/../b"       "b"          "/b"
--       "a/b/../c"     "a/c"        --
--
local function cleanPath(path)
   local n, e, post = 1
   repeat
      n, e, post = path:match("/()(%.%.?)([^/]?)", n)
      if n and post=="" then
         if e == "." then
            path = path:sub(1,n-1) .. path:sub(n+2)
         else
            local pre, a = dir(path, n-2)
            local parent = path:sub(a+1,n-2)
            if parent ~= ".." then
               if parent == "" then pre = pre .. "/" end
               path = pre .. path:sub(n+3)
               n = a
            end
         end
      end
   until not n

   return path
end


-- Combine relative URI 'r' with base URI 'b'.  May return a table or a
-- string.  Tables might NOT have 'path' fields.
--
local function resolve(r, b)
   r = uriToTable(r)
   b = uriToTable(b)

   local path, pb = r.path or "", b.path or ""
   if r.scheme then
      -- do not inherit anything from path
   elseif path == "" then
      path = pb
   elseif path:sub(1,1) ~= "/" then
      path = dir(pb, #pb) .. path
   end
   path = cleanPath( path )

   return {
      scheme  = r.scheme or b.scheme,
      authority    = r.authority or (not r.scheme and b.authority or nil),
      path    = path,
      version = r.version or b.version,
      params  = r.params,
      fragment = r.fragment
   }
end


-- Generate table representation of URI.  Combine with 'base' is given.
-- Either 'uri' or 'base' may be in string or table form.
--
local function parse(uri, base)
   if base then
      uri = resolve(uri, base)
   end
   return uriToTable(uri)
end


-- Generate a canonical string representation of URI.  Combine with 'base'
-- is given.  Either 'uri' or 'base' may be in string or table form.
--
local function gen(uri, base)
   if base then
      uri = resolve(uri, base)
   end
   return uriToString( uriToTable(uri) )
end


return {
   parse = parse,
   gen   = gen,
   cleanPath = cleanPath,
   byteToHex = byteToHex,
   pctDecode = pctDecode,
   paramDecode = paramDecode
}
