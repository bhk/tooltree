'use strict';

// Returns `memoFunc`, a memoization of `func`.
//
// `memoFunc.flush()` releases all cache entries that have not been accessed
// since the last call to `memoFunc.flush()`.
// 
// When `func` is called, its `this` parameter will be set to an object
// that represents the cache entry.  It may assign a property named `onflush`
// to a function that will be called if and when the cache entry is removed
// as a result of a call to `memoFunc.flush()`.  `onflush` will also be called
// with `this` set to the cache entry.
//
function memoize(func) {
    var cache = { k: [], v: [] };

    // Memoized version of `func`
    //
    function memoFunc() {
        var map = cache;
        for (var argn = 0; argn < arguments.length; ++argn) {
            var arg = arguments[argn];
            var ndx = map.k.indexOf(arg);
            if (ndx < 0) {
                map.k.push(arg);
                map.v.push( map = { k: [], v: [] });
            } else {
                map = map.v[ndx];
            }
        }
        map.fresh = true;
        return ('value' in map
                ? map.value
                : (map.value = func.apply(map, arguments)));
    }

    // Return `true` if map should be discarded
    //
    function flushMap(map) {
        var values = map.v;
        var keys = map.k;

        for (var ndx = values.length; --ndx >= 0; ) {
            if (flushMap(values[ndx])) {
                // remove map
                var v = values.pop();
                var k = keys.pop();
                if (ndx < values.length) {
                    values[ndx] = v;
                    keys[ndx] = k;
                }
            }
        }

        if (map.fresh) {
            map.fresh = false;
            return false;
        }
        if ('value' in map) {
            // remove entry
            if (map.onflush) {
                map.onflush();
                map.onflush = null;
            }
            delete map.value;
        }
        return !values.length;
    }

    memoFunc.flush = flushMap.bind(null, cache);

    return memoFunc;
};

module.exports = memoize;
