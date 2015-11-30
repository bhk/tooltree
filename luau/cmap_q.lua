-- cmap_q.lua

local qt = require "qtest"
local map = require "cmap"

local eq = qt.eq

-- cmap returns a table of constructors, named "i", "x", "xi", and "ix".
-- These constructors return *map* functions -- functions that transform a
-- table into another table.
--
-- Map functions may be constructed from strings that describe how each
-- element is to be transformed.  Each string is a Lua expression that is
-- evaluated in a context where "k" and "v" are bound to the key and value
-- of the table element being processed.  For example, map.i("v*2")
-- constructs a map function that multiplies every value in an array by two.
--
-- The meanings of "i", "x", "xi", and "ix" are illustrated below:

local function sort(a, cmp)
   table.sort(a, cmp)
   return a
end


-- map.i:  array -> array

eq( {3,5,9},           (map.i"v+1"){2,4,8} )
eq( {1,2,3},           (map.i"k"){2,4,8} )
eq( {1,3,9},           (map.i"v.x"){ {x=1,y=2}, {x=3}, {x=9} } )
eq( {2,3,4},           (map.i"v<5 and v or nil"){2,3,4,5,6,7} )

-- map.x:  hash  -> hash

eq( {a=1,b=2,c=3},     (map.x"v,k"){"a","b","c"} )
eq( {5,6,7,a=3},       (map.x"k,v+1"){4,5,6,a=2} )

-- map.ix: array -> hash

eq( {5,6,7},           (map.ix"k,v+1"){4,5,6,a=2} )
eq( {[2]=4,[3]=5},     (map.ix"k+1,v"){4,5} )
eq( {a=1,b=2,c=3},     (map.ix"v,k"){"a","b","c"} )

-- map.xi: hash  -> array

eq( {"ax","by"},       sort((map.xi"k..v"){a="x",b="y"}) )
eq( {"ax","by"},       sort((map.xi"k..v"){a="x",b="y"}) )

-- Since the map.* constructors return memotables, they can be used
-- as tables as well as functions.

eq( {3,5,9},           (map.i["v+1"]){2,4,8} )

-- Cloning the array elements of a table reduces to:

eq( {2,4,8},           map.i.v{2,4,8,x=true} )

-- Extract an array of keys from a hash:

local t = map.xi.k{a=3,b=5,c=7}
table.sort(t) -- order of keys is not deterministic
eq( {"a","b","c"},     t)

-- Constructors may take functions instead of strings.  Functions that
-- operate on array elements are passed (v,k), not (k,v).  Functions return
-- v when constructing an array, and return k,v when constructing a hash.

eq( {"A","B","C"},     map.i(string.upper){"a","b","c"} )
eq( {{1,2},{3,4}},     map.i(map.i.v){{1,2,x=true},{3,4,x=false}} )
eq( {aa=1,bb=4},       map.x(function(k,v) return v..v,k*k end){"a","b"} )
eq( {aa=1,bb=4},       map.ix(function(v,k) return v..v,k*k end){"a","b"} )

