'use strict';

var m1 = require('memoize.js');
var m2 = require('memoize2.js');

var expect = require('expect.js');
var eq = expect.eq;


function test(memoize) {

    var flushed = [];
    function onflush() {
        flushed.push(this.value);
    }

    var count = 0;
    function f(a) {
        this.onflush = onflush;
        ++count;
        return a;
    }

    var mf = memoize(f);

    // remembers results & distinguishes between arguments

    eq(1, mf(1));
    eq(1, mf(1,2));
    eq(1, mf(1,{}));
    eq(1, mf(1,2,3));
    eq(4, count);

    // cached entries do not call f() again
    eq(1, mf(1,2,3));
    eq(1, mf(1,2,3));
    eq(4, count);

    mf.flush();
    eq(0, flushed.length);

    eq(1, mf(1,2,3));   // touch old entry
    eq(4, count);
    eq(3, mf(3));       // add new entry
    eq(5, count);

    mf.flush();
    eq([1,1,1], flushed);

    eq(3, mf(3));       // re-touch 3
    eq(5, count);

    flushed = [];
    mf.flush();
    eq([1], flushed);

    mf.flush();
    eq([1,3], flushed);
}


test(m1);

test(m2);


function clock(memoize, name) {
    var Clocker = require('clocker.js');

    function f(a) {
        return a;
    }
    function callback() {
    }

    var mf = memoize(f, callback);

    function work() {

        for (var n = 0; n < 50; ++n) {
            mf(n, 1, 5);
            mf(1, n, 5);
            mf(1, 5, n);
            mf(1, 5);
        }
        mf.flush();
        for (n = 0; n < 50; ++n) {
            mf(n, 1, 5);
            mf(1, n, 7);
            mf(1, 7, n);
            mf(1, 5);
        }
        mf.flush();
    }


    Clocker.show(work, 100, name);
}

if (process.env.DOBENCH) {
    clock(m1, 'm1');
    clock(m2, 'm2');
}
