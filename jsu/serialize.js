// serialization
//
// Convert values to string -- not always valid JavaScript source. The main
// requirement is capturing behavior and content for the purpose of
// expect.eq().
//
// Only the *own* properties of objects are serialized, including
// "non-enumerable" ones (which are flagged with a "!" prefix).
//
// Recursive references to objects or arrays are represents by "@N", where N
// is the index of the parent from the top of the structure.
'use strict';

var idRE = /^[a-zA-Z_$][a-zA-Z0-9_$]*$/;

var prototypes = [];


function isObject(v) {
    return typeof v === 'object' && v !== null;
}


function getPrototypeName(obj) {
    var p = Object.getPrototypeOf(obj);
    if (p === Object.prototype) {
       return 'Object.prototype';
    } else if (p === Array.prototype) {
        return 'Array.prototype';
    } else if (! isObject(p)) {
        return serialize(p);
    }

    // assign name to unknown prototype
    var ndx = prototypes.indexOf(p);
    if (ndx == -1) {
        ndx = prototypes.length;
        prototypes[ndx] = p;
    }
    return 'unk' + ndx;
}


function serialize(x) {
    return ser([], x);
}


function ser(parents, x) {
    var result;

    if (typeof x === 'string') {
        return "'" + x.replace(/[\\']/, '\\$1').replace('\n', '\\n') + "'";
    }
    if (typeof x === 'function') {
        parents.seen = parents.seen || [];
        var ndx = parents.seen.indexOf(x);
        if (ndx < 0) {
            ndx = parents.seen.push(x) - 1;
        }
        return 'Function[' + ndx + ']';
    }
    if (!isObject(x)) {
        return String(x);
    }

    var pndx = parents.indexOf(x);
    if (pndx >= 0) {
        // "@0" = self, "@1" = parent, ...
        return '@' + (parents.length - pndx - 1);
    }

    parents.push(x);

    var protoName = getPrototypeName(x);
    var a = [];
    var aIndex = Object.create(null);
    var ownNames = Object.getOwnPropertyNames(x).sort();

    if (protoName === 'Array.prototype') {
        // make simple arrays look like array literals
        for (var ndx = 0; ndx < x.length; ++ndx) {
            var value = x[ndx];
            a.push(ser(parents, value));
            aIndex[ndx] = true;
        }
        aIndex.length = true;
    }

    ownNames.forEach( function (key) {
        if (key in aIndex) {
            return;
        }
        var value;
        try {
            value = x[key];
        } catch (x) {
            value = '<ERROR!>';
        }

        var d = Object.getOwnPropertyDescriptor(x, key);

        a.push( (d.enumerable ? '' : '~') +
                (idRE.test(key) ? key : ser(parents, key)) + ':' +
                ser(parents, value) );
    });

    if (protoName === 'Array.prototype') {
        result = '[' + a.join(',') + ']';
    } else {
        if (protoName !== 'Object.prototype') {
            a.push('__proto__:' + protoName);
        }
        result = '{' + a.join(',') + '}';
    }

    parents.pop();
    return result;
}

module.exports = serialize;
