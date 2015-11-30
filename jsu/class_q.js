'use strict';

var Class = require("class.js");
var expect = require("expect.js");


// ASSERTION: `create` establishes inheritance chain
// ASSERTION: `binitialize` is optional

var A = Class.subclass();

A.fna = function () {
    return 1;
};

var a = A.create();
expect.eq(1, a.fna());
expect.assert(a !== A);


// ASSERTION: `subclass` establishes inheritance chain

var B = A.subclass();
expect.eq(B.fna, A.fna);
expect.eq(1, B.fna());


// ASSERTION: `create` calls `initialize` when defined

B.initialize = function (x, y) {
    this.b = x + y;
};

B.fnb = function () {
    return this.fna() + this.b;
};

var b = B.create(2, 3);

expect.eq(5, b.b);
expect.eq(6, b.fnb());

// ASSERTION: `hasInstance` identifies objects created via `subclass` and `create`

expect.assert(Class.hasInstance(A));
expect.assert(Class.hasInstance(B));
expect.assert(Class.hasInstance(b));
expect.assert(A.hasInstance(B));
expect.assert(A.hasInstance(b));
expect.assert(B.hasInstance(b));
expect.assert(! A.hasInstance(Class));
