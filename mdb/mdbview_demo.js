// mdbview_demo.js

'use strict';

var demo = require('demo.js');
var serialize = require('serialize.js');
var mdb = require('mdb_emu.js');
var MDBView = require('mdbview.js');


mdb.openValue = function (desc) {
    demo.log("open: " + desc);
};

var mdbView = MDBView.create(mdb);

demo.init({
    position: 'relative',
    margin: 0,
    border: '2px solid #aaa'
});

demo.append(mdbView);

document.body.style.background = '#bbb';

window.onresize = function() {
    demo.content.e.style.height = (window.innerHeight - 180) + 'px';
};
window.onresize();

demo.note(
    'Go transitions to "exit"',
    'StepIn/StepOut change stack depth',
    'StepOver spends 2 seconds in "run" state',
    'bar.lua is very short; baz.lua is very long'
);

// display breakpoints

demo.log( ['Breakpoints: ', demo.value(mdb.breakpoints)] );


var modeSaved;
demo.addButton('Disconnect', function () {
    if (mdb.mode.getValue() != 'down') {
        modeSaved = mdb.mode.getValue();
        mdb.mode.setValue('down');
    }
});

demo.addButton('Connect', function () {
    if (mdb.mode.getValue() == 'down') {
        mdb.mode.setValue(modeSaved);
    };
});


demo.addButton('Busy', function () {
    if (mdb.mode.getValue() != 'busy') {
        modeSaved = mdb.mode.getValue();
        mdb.mode.setValue('busy');
    }
});


demo.addButton('NotBusy', function () {
    if (mdb.mode.getValue() == 'busy') {
        mdb.mode.setValue(modeSaved);
    };
});


demo.addButton('LOADTIME=0', function () {
    mdb.LOADTIME = 0;
});

demo.addButton('LOADTIME=100', function () {
    mdb.LOADTIME = 100;
});

demo.addButton('LOADTIME=1000', function () {
    mdb.LOADTIME = 1000;
});

window.mdb = mdb;
