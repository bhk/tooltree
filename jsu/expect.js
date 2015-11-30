// expect.js: unit test help for Node.js
//
//   expect.eq(expected, got, [level])
//   expect.log(...)
//   expect.printf(...)
//   expect.fail(str, [level])
//   expect.assert(cond)
//   expect.serialize(a)
//   expect.eqTest(a, b)
//
// expect.eq() is preferable to Node's assert functions, because:
//
//    - assert.equal() performs type coercion, which is almost never
//      appropriate for a unit test.  (When do you *not* care whether your
//      function returns a string or number?)
//
//    - assert.strictEqual() does not compare arrays and objects based
//      on their content.  expect.eq() does, so expect.eq([1,2], [1,2]) will
//      succeed, which is almost always what is desired in a unit test.
//
//    - The 'level' parameter allows other assertion functions to be
//      built atop 'eq' without generating confusing stack traces.
// 
// expect.log(...) is preferable to console.log() because console.log()
//      buffers output, which may result in data being lost when the program
//      aborts unexpectedly.


'use strict';

var fs = require('fs');
var serialize = require('serialize.js');


// Write to stderr (non-buffered).
//
function log() {
    var a = [];
    for (var ndx in arguments) { a.push(arguments[ndx]); }
    a.push("\n");
    fs.writeSync(2, a.join(""));
};


exports.exit = process.exit.bind(process);

function fail (str, level) {
    level = level || 0;
    var o = {};
    Error.stackTraceLimit = 20;
    Error.captureStackTrace(o, fail);
    var s = o.stack;

    for (var n = 0; n <= level; ++n) {
        s = s.replace(/^[^\n]*\n/, '');
    }
    log('Assertion failed:\n' + str + '\n' + s + '\n');
    exports.exit(1);
}

var ts = Object.prototype.toString;

var checkValues = {};
checkValues[ts.call(new Number)] = true;
checkValues[ts.call(new Boolean)] = true;
checkValues[ts.call(new String)] = true;
checkValues[ts.call(new Date)] = true;

// eqTest: Return true if 'a' and 'b' are equivalent.
// 
var eqTest = function (a, b) {
    return a === b || serialize(a) === serialize(b);
};


function printf(fmt) {
    var argno = 1;
    var a = arguments;
    function repl(s) {
        if (s == '%%') {
            return '%';
        } else if (s == '%s') {
            return String(a[argno++]);
        } else if (s == '%q' || s == '%Q') {
            return serialize(a[argno++]);
        } else {
            throw new Error('unsupported format string: ' + s);
        }
    }
    fs.writeSync(2, fmt.replace(/%./g, repl));
}


exports.log = log;
exports.printf = printf;
exports.fail = fail;
exports.eqTest = eqTest;
exports.serialize = serialize;

// eq: Display message and exit program if `expected` is not equivalent to `got`.
// level = number of stack frames to omit from stack trace
//     0 => caller of exports.eq will be at top of trace
//     1 => caller of caller of exports.eq ...
//    
exports.eq = function(expected, got, level) {
    if (!eqTest(expected, got)) {
        fail('A: ' + serialize(expected) + '\n' + 
             'B: ' + serialize(got), (level || 0) + 1);
    }
};


exports.assert = function(cond) {
    if (!cond) {
        fail('Assertion failed!', 1);
    }
};
