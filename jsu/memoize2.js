'use strict';

var Map = require('map.js');

function newMap() { return new Map; }


function memoize(func, flushCallback) {
    var cache = newMap();

    // Memoized version of `func`
    //
    function memoFunc () {
        var map = cache;
        for (var argn = 0; argn < arguments.length; ++argn) {
            var arg = arguments[argn];
            map = map.make(arg, newMap);
        }
        map.fresh = true;
        return ('value' in map
                ? map.value
                : (map.value = func.apply(map, arguments)));
    }

    // Return `true` if array should be discarded
    //
    function flushMap(map) {
        map.forEach(function (value, key) {
            if (flushMap(value)) {
                map.delete(key);
            }
        });

        if (map.fresh) {
            map.fresh = false;
            return false;
        }
        if ('value' in map) {
            if (map.onflush) {
                map.onflush();
                map.onflush = null;
            }
            delete map.value;
        }
        return !map.size;
    }

    // Release all cache entries that have not been retrieved since the last
    // flush.  Calling flush() twice in succession will empty the cache.
    //
    memoFunc.flush = flushMap.bind(null, cache);

    return memoFunc;
};


module.exports = memoize;
