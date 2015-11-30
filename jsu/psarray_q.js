'use strict';

var PSArray = require("psarray.js");
var expect = require("expect.js");


function extract(psa) {
    var a = [];
    psa.forEach(function (value) { a.push(value); });
    return a;
}


var a = PSArray.create([9,8]);

expect.eq(a.a, [9,8]);
expect.eq(a.length, 2);
expect.eq(extract(a), [9,8]);

var b = a.push(7);

expect.eq(b.a, [9,8,7]);
expect.assert(a.a === b.a);

var c = a.push(6);
var d = c.push(5);

expect.eq(extract(b), [9,8,7]);
expect.eq(extract(c), [9,8,6]);
expect.eq(extract(d), [9,8,6,5]);

expect.eq(b.diff(a), {index:2, numDel: 0, numIns: 1});

expect.eq(d.diff(a), {index:2, numDel: 0, numIns: 2});

expect.eq(d.diff(b), {index:2, numDel: 1, numIns: 2});

expect.eq(b.diff(d), {index:2, numDel: 2, numIns: 1});


// Future?
//
//  psa.map(fn) --> psaNew
//  psa.set(ndx, value) --> b
//  psa.replace(ndxStart, numDel, values) --> b
//  psa.slice(ndxStart, ndxEnd)
//
//  Note: JavaScript's Array.prototype.concat(x) might put `x` at the end of
//        `a`.  Or, it might put the *contents* of `x` at the end of `a`.
// 
// PSArray.map = function (fn) {
//     var a = new PSArray();
//     for (var ndx = 0; ndx < this.length; ++ndx) {
//         a.push(fn(this.a[ndx]));
//     }
//     return a;
// };
// 

