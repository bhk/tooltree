// PSArray : array as a persistent data structure.  See psarray.txt.

"use strict";

var PSArray = require("class.js").subclass();


PSArray.initialize = function (a, len) {
    this.a = a || [];
    this.length = (len != null ? len : this.a.length);
};


PSArray.get = function (ndx) {
    return (ndx < this.length ? this.a[ndx] : undefined);
};


PSArray.push = function () {
    var a = this.a;
    var index = this.length;
    for (var argn = 0; argn < arguments.length; ++argn, ++index) {
        var value = arguments[argn];
        if (index < a.length && a[index] !== value) {
            a = a.slice(0, index);
        }
        a[index] = value;
    }
    return PSArray.create(a);    
};


PSArray.forEach = function (fn, thisArg) {
    for (var ndx = 0; ndx < this.length; ++ndx) {
        fn.call(thisArg, this.a[ndx], ndx);
    }
};


PSArray.diff = function (old) {
    // optimize only for insertions/deletions at the end
    var ndx = Math.min(old.length, this.length);
    if (old.a !== this.a) {
        var max = ndx;
        for (ndx = 0; ndx < max && old.a[ndx] === this.a[ndx]; ++ndx)
            ;
    }

    return {
        index: ndx,                 // position at which diff starts
        numDel: old.length - ndx,   // number deleted from old array
        numIns: this.length - ndx   // number added to new array
    };
};


module.exports = PSArray;
