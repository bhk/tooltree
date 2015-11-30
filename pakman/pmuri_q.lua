-- pmuri_q.lua

local qt = require "qtest"

-- @require pmuri
local U, _U = qt.load("pmuri.lua", {
                         "paramEncode", "paramDecode", "pathEncode",
                         "cleanPath", "parseParams", "makeParams",
                         "uriToString", "uriToTable",
                      })

local T, eq = qt.tests, qt.eq

local gen, parse = U.gen, U.parse


function T.byteToHex()
   return qt.eq("%20", U.byteToHex(" "))
end

function T.paramEncDec()
   local function t(d,e,e2)
      -- d = decoded,   e = canonical encoding,  e2 = equivalent encoding
      qt._eq(e, _U.paramEncode(d), 2)
      qt._eq(d, _U.paramDecode(e), 2)
      if e2 then
         qt._eq(d, _U.paramDecode(e2), 2)
      end
   end

   t( "a\1\127", "a%01%7F", "%61%01%7f")
   t( "a b",     "a+b",  "a%20b")
   t( "a=;&",    "a%3D%3B%26")
   t( [[!"#$%&'()*+,-./0123456789:;<=>?@[\]^_`{|}~]],
      [[!%22%23%24%25%26%27()*%2B%2C-.%2F0123456789%3A%3B%3C%3D%3E%3F%40%5B%5C%5D%5E_%60%7B%7C%7D~]] )

   -- path encoding/decoding
   eq("/a%20b+c", _U.pathEncode("/a b+c"))
   eq("/a b+c", U.pctDecode("/a%20b+c"))
   eq("/a/b", U.pctDecode("/a%2Fb"))
end


function T.params()

   local function t(tbl, str, str2)
      qt._eq(tbl, _U.parseParams(str), 2)
      if str2 then
         qt._eq(tbl, _U.parseParams(str2), 2)
      end
      qt._eq(str, _U.makeParams(tbl), 2)
   end

   -- a) URI encoding/decoding is performed on names & values
   -- b) When no "=" is present, numeric indices 1, 2, etc., are used
   -- c) Fields are ordered deterministically.

   t({a="b"},        "a=b")
   t({a="b",c="d"},  "a=b;c=d",  "c=d&a=b")
   t({a=""},         "a=", "a=;")
   t({[""]="b"},     "=b")

   t({"a"},          "a")
   t({"a","b"},      "a;b")

   t({"p","q",a="b",x="",y="z"},  "p;q;a=b;x=;y=z", "a=b&x=;p;;y=z&q")
   t({ab="c~"},                   "ab=c~", "%61b=c%7e")

   t({}, nil)

   -- c) Table entries with 'false' values are treated as non-existent.

   eq("a=b", _U.makeParams{a="b", c=false})

end


function T.cleanPath()
   local function e(i,o)
      return eq(o, _U.cleanPath(i))
   end

   -- Input            , Output
   e( ""               , ""      )
   e( "/"              , "/"     )
   e( "/a"             , "/a"    )
   e( "/a/"            , "/a/"   )
   e( "/a/b/"          , "/a/b/" )
   e( "/dir/."         , "/dir/" )
   e( "/dir/f/.."      , "/dir/" )
   e( "/a/../b/f"      , "/b/f"  )
   e( "/.."            , "/"     )
   e( "/."             , "/"     )
   e( ".."             , ".."    )
   e( "a/../.."        , ".."    )
   e( "."              , "."     )
   e( "a/.."           , ""      )
   e( "../.."          , "../.." )
   e( "../a"           , "../a"  )
   e( "a/../b"         , "b"     )
   e( "a/b/../c"       , "a/c"   )
   e( "/a/b/../c/"     , "/a/c/" )
   e( "/a/b/../../d"   , "/d"    )

   e(  "/."            ,  "/"    )
   e( "./"             , "./"    )
   e( "/./"            , "/"     )
   e( "/a/."           , "/a/"   )
   e( "/a/./"          , "/a/"   )
   e( "/a/b/.."        , "/a/"   )
   e( "../.."          , "../.." )
   e( ".././.."        , "../.." )
end


function T.uriToTable()
   local function e(u,s,h,p,v,a,f)
      local t = _U.uriToTable(u)
      qt._eq(s, t.scheme, 2)
      qt._eq(h, t.host, 2)
      qt._eq(p, t.path, 2)
      qt._eq(v, t.version, 2)
      qt._eq(a, t.params, 2)
      qt._eq(f, t.fragment, 2)
   end

   -- valid scheme characters: alpha, digit, "+", "-", "."
   e("a-b+c.d:",  "a-b+c.d", nil,  "",  nil)
   e("a*b:foo",   nil,       nil,  "a*b:foo")
   e("a?b:foo",   nil,       nil,  "a",  nil, {"b:foo"})

   e("s://h/p@2", "s",   "h",   "/p",  "2")
   e("//h/p@2",   nil,   "h",   "/p",  "2")
   e("p@2",       nil,   nil,   "p",   "2",  nil)
   e("@2?a",      nil,   nil,   "",    "2",  {"a"})
   e("/a?a",      nil,   nil,   "/a",  nil,  {"a"})

   e("s://h/p@2?x=1", "s",   "h",   "/p",  "2", {x="1"})

   e("a?x=http://foo", nil, nil, "a",  nil, { x = "http://foo" } )

   -- fragments
   e("/abc#def",   nil,   nil,   "/abc",  nil,  nil, "def")
   e("/abc#%44",   nil,   nil,   "/abc",  nil,  nil, "D")
   e("/a?p#def",   nil,   nil,   "/a",    nil,  {"p"}, "def")
   e("xx:#def",    "xx",  nil,   "",      nil,  nil, "def")
   -- hmmm...
   --e("xx://a#def", "xx",  "a",   "",      nil,  nil, "def")
end


function T.uriToString()
   local function e(o, s, h, p, v, a, f)
      eq(o, _U.uriToString{ scheme=s, host=h, path=p, version=v, params=a, fragment=f})
   end
   e( "s://h/p@v", "s", "h", "p", "v")
   e( "s://h/",    "s", "h", "", false)
   e( "/abc#def",  nil,  nil, "/abc", nil, nil, "def")
   e( "/abc#%23",  nil,  nil, "/abc", nil, nil, "#")
end


function T.gen_and_parse()
   local function e(o, ...)
      local og = gen(...)
      qt._eq(o, og, 2)
      local op = parse(...)
      local opg = gen(op)
      qt._eq(o, opg, 2)
      qt._eq(og, opg, 2)
   end

   -- from table
   e("s://h/p@v?p;a=b", { scheme = "s", host = "h", path = "/p",
                          version = "v", params = { "p", a="b"}} )
   e("?p;a=b", { params = { "p", a="b"}} )
   e("", {})

   -- from string (canonicalize/normalize)
   e("s://h/p@v?p;a=b", "S://h/p@v?a=b;p")
   e("s://h/", "s://h")
   e("s://h/%9A%AF%25ua", "s://h/%9A%af%u%61")

   e("?a;x=%3A%2F%3F",    { params={"a", x=":/?"} })
   e("p4://host/a",       "a", "p4://host/base")
   e("p4://host/base/a",  "a", "p4://host/base/")
   e("../a",              "a", "../")
   e("base/a@1?x",        "a?x", {path="base/", version="1"})
   e("?a;x=%3A%2F%3F",    "?x=:/?&a")
   e("foo@2%3A%2F%403",   "foo@2:/@3")

   -- resolve
   e("s://h/p@v?p;a=b", { path="/p", params={"p",a="b"} }, "s://h/foo@v" )
   e("s://h/p@v?p;a=b", "/p?a=b;p", { scheme = "s", host = "h", version = "v"})
   e( "s://h/a/@2",    "@2",        "s://h/a/.@10")
   e( "s://h/a/b@10",  "b",         "s://h/a/.@10")
   e( "s://h/a/b@10",  "b@10",      "s://h/a/.")
   e( "s://h/a/b@2",   "b@2",       "s://h/a/.@10")
   e( "s://h/a/b",     "b",         "s://h/a/.")
   e( "s://h/c@10",    "/c",        "s://h/a/b@10")
   e( "s://h/c@2",     "/c@2",      "s://h/a/b@10")
   e( "s://h/a/c@2",   "c@2",       "s://h/a/b@10")
   e( "s://g/c@10",    "//g/c",     "s://h/a/b@10")
   e( "t://g/c@10",    "t://g/c",   "s://h/a/b@10")
   e( "t://g/c@2",     "t://g/c@2", "s://h/a/b@10")
   e( "s://h/a/b/@10", ".",         "s://h/a/b/c@10")
   e( "s://h/a/@10",   "..",        "s://h/a/b/c@10")
   e( "s://h/@10",     "../..",     "s://h/a/b/c@10")
   e( "s://h/@10",     "../../..",  "s://h/a/b/c@10")

   e( "foo:xyz",       "foo:xyz",   "s://h/a/b/c")

   e( "s://h/a?x=1",    "?x=1",     "s://h/a")
   e( "/a/b?x=1",       "?x=1",     "/a/b")
   e( "/a/b@23",        "@23",      "/a/b")
   e( "/a/b",           "",         "/a/b?x=1")

   -- resolve fragments
   e( "/a/b?p#f",       "b?p#f",    "/a/")

   -- gen() returns new table:
   local t = {path="/"}
   eq(false, t == gen(t))

   -- parse() returns pct-decoded values
   eq( {path="/a/b", version=":", params={"?"}},  parse("/a%2Fb@%3A?%3F"))
end


function T.docs()
   eq({path="p", params={"a", x=":/?"}}, parse("p?a;x=%3A%2F%3F"))
   eq("?a;x=%3A%2F%3F",   gen({ params={"a", x=":/?"} }))
   eq("?a;x=%3A%2F%3F",   gen("?x=:/?&a"))
   eq("p4://host/a",      gen("a", "p4://host/base"))
   eq("p4://host/base/a", gen("a", "p4://host/base/"))
   eq("../a",             gen("a", "../"))
   eq("base/a@1?x",       gen("a?x", {path="base/", version="1"}))
   eq("/a/pak?x=1",       gen("?x=1", "/a/pak"))
end

return qt.runTests()
