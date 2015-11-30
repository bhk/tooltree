// clocker
'use strict';

exports.MIN_TIME = 500;
exports.FACTOR = 1.05;


// Increase number of repetitions until the test runs at least MIN_TIME
// milliseconds.  As we increase repetitions, VM optimizations may decrease
// run times, so some number of cycles may be required before completion.
// Higher MIN_TIME values and FACTOR values approaching 1 will help ensure
// run times to settle near their optimal levels.
//
exports.time = function (fn) {
    var reps = 1;
    var t;

    for (;;) {
        var t0;
        var tSync = Date.now();
        while (tSync == (t0 = Date.now()))
            ;
        for (var n = reps; n > 0; --n) {
            fn();
        }
        t = Date.now() - t0;
        if (t > exports.MIN_TIME)
            break;

        reps *= exports.FACTOR * exports.MIN_TIME / (t+1);
    }
    return t * (1000000 / reps);
};


function format(n, decimals) {
    var mul = Math.pow(10, decimals);
    var s = String(Math.round(n * mul));
    while (s.length <= decimals) {
        s = '0' + s;        
    }
    return s.substr(0, s.length - decimals) +
        (decimals > 0
         ? '.' + s.substr(-decimals)
         : '');
}

// var eq = require('expect.js').eq;
// eq(format(123.456, 0), '123');
// eq(format(123.456, 1), '123.5');
// eq(format(123.456, 4), '123.4560');
// eq(format(0.0900, 0), '0');
// eq(format(0.0009, 1), '0.0');
// eq(format(0.0987, 5), '0.09870');


// `divisor` represents the number of operations performed by the work
// function
//
exports.show = function (fn, divisor, name) {
    divisor = divisor || 1;
    name = name || fn.name;
    var ns = exports.time(fn);
    console.log( format(ns / divisor, 2) + 'ns : ' + name 
                 + (divisor == 1 ? '' : ' (/' + divisor + ')'));
};

