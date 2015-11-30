'use strict';

var CodeView = require('codeview.js');
var demo = require('demo.js');
var O = require('observable.js');
var sampleLua = require('samplelua.js');

demo.init({
    height: 300,
    backgroundColor: 'red'
});

var cv = CodeView.create();

demo.append(cv);


var bpLines = O.slot();
var bpcount = 127;
function setBP() {
    var a = [];
    ++bpcount;
    for (var n = 1; n < 10; ++n) {
        if (bpcount & Math.pow(2, n-1)) {
            a.push(n+4);
        }
    }
    bpLines.setValue(a);
}
setBP();

cv.setText(sampleLua.text, bpLines);


demo.addButton('Null', function () {
    cv.setText(null);
});


demo.addButton('Short', function () {
    var text = sampleLua.lines.slice(0, 12).join('\n');
    cv.setText(text, bpLines);
});


demo.addButton('Long', function () {
    var reps = window.LONG || 20;
    var text = sampleLua.text;
    for (var n = 1; n < reps; ++n) {
        text = text + sampleLua.text;
    }
    cv.setText(text, bpLines);
});


demo.addButton('Flag 1', cv.flagLine.bind(cv, 1));
demo.addButton('Flag 21', cv.flagLine.bind(cv, 21));
demo.addButton('Flag 100', cv.flagLine.bind(cv, 100));

demo.note(
    'Text area should scroll up/down and left/right when text does not fit',
    'Gutter should scroll up/down but stay anchored to left side of CodeView',
    'Clicking on a gutter line should set/clear a breakpoint',
    'Hovering over a gutter line shows outline of breakpoint indicator',
    'Active state state (depressed) gutter line shows solid breakpoint indicator',
    'Flagging a line should scroll it into view'
);

// display breakpoints

demo.log( ['Breakpoints: ', demo.value(bpLines)] );

