'use strict';

require('dom_emu.js');
require('settimeout_emu.js');
var Bubble = require('bubble.js');
var demo = require('demo.js');
var O = require('observable.js');
var expect = require('expect.js');


var oc = O.slot();

var b = Bubble.create({
   backgroundColor: 'blue',
   $caption: 'caption',
   $content: oc
});


oc.setValue("This is a test");

window.setTimeout.flush();

expect.eq(b.e.textContent, 'captionThis is a test');

