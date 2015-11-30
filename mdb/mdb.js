// mdb.js
//
// `mdb` represents the debugger state, enacpsulating communication with the
// web server.
//
// Observables:
//
//    mdb.mode          'down', 'start', 'run', 'pause', 'exit', 'error'
//    mdb.stack         array of stack frames
//    mdb.breakpoints   map: filenames -> array of breakpoint lines
//    mdb.console       array of console entries
//
// Observable constructors:
//
//    mdb.fetchSource
//    mdb.fetchLocals
//    mdb.fetchTablePairs
//
// Functions that send data to the server:
//
//    mdb.action
//    mdb.sendCommand
//    mdb.breakpoints.setValue
//
// UI-related functions:
//
//    mdb.openValue

'use strict';

var xhttp = require('xhttp.js');
var OWeb = require('oweb.js');
var scheduler = require('scheduler.js');
var O = require('observable.js');


var mdb = {};

var oweb = OWeb.create(xhttp, scheduler, "/observe");


//----------------------------------------------------------------
// MDB

mdb.mode = O.func(function (mode) {
    return mode || 'down';
}, oweb.observe('mode'));


mdb.stack = oweb.observe('stack');


mdb.console = oweb.observe('console');


mdb.breakpoints = oweb.observe('breakpoints');


mdb.breakpoints.setValue = function (value) {
    xhttp({ uri: "/breakpoints",
            method: 'PUT',
            body: JSON.stringify(value) });
};


mdb.fetchLocals = function (index) {
    return oweb.observe('vars/' + index);
};


mdb.fetchTablePairs = function (desc) {
    var id = String(desc).match(/\d*$/)[0];
    return oweb.observe('pairs/' + id);
};


mdb.fetchSource = function (filename) {
    return oweb.fetch('/source' + xhttp.makeQuery({ name: filename }));
};


mdb.sendCommand = function (cmd) {
    xhttp( {method: 'POST', uri: '/console', body: cmd} );
};


mdb.action = function (name) {
    var actions = {
        restart: '/restart',
        go: '/run/',
        stepOver: '/run/over',
        stepIn: '/run/in',
        stepOut: '/run/out',
        pause: '/pause'
    };
    var action = actions[name];

    if (action) {
        xhttp(action);
    } else {
        alert('not yet implemeted: ' + name);
    }
};


mdb.openValue = function () {
    // TODO
};


module.exports = mdb;
