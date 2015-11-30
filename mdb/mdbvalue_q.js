// mdbvalue_q.js

'use strict';

require('dom_emu.js');
var expect = require('expect.js');
var MDBValue = require('mdbvalue.js');

var mdb = {};

mdb.fetchTablePairs = function () {
    throw new Error('unsupported');
};

mdb.openValue = function (desc) {};

var mv = MDBValue.create(mdb);

var eq = expect.eq;


// ASSERT descToType works for valid Value Descriptions

eq('nil', mv.descToType('nil'));
eq('boolean', mv.descToType('true'));
eq('boolean', mv.descToType('false'));
eq('number', mv.descToType('1.2e9'));
eq('number', mv.descToType('-123.4'));
eq('string', mv.descToType('"hello"'));
eq('table', mv.descToType('table 3'));
eq('function', mv.descToType('function 123'));
eq('userdata', mv.descToType('userdata 9'));
eq('thread', mv.descToType('thread 1'));


// ASSERT creating each typeof value succeeds

var v;

v = mv.createValueView('123');
v = mv.createValueView('"hi"');
v = mv.createValueView('function 1');
v = mv.createValueView('userdata 1');
v = mv.createValueView('thread 3');
v = mv.createValueView('true');
v = mv.createValueView('nil');
v = mv.createValueView('table 1');
v = mv.createValueView('table 2');
v = mv.createValueView('table 3');
