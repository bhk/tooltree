var expect = require("expect.js");
require('dom_emu.js');
var scheduler = require("scheduler_emu.js");

var eq = expect.eq;
var assert = expect.assert;


//--------------------------------
// Test Anim
//--------------------------------

var AnimFactory = require("anim.js");
var Anim = AnimFactory.newClass(scheduler);

var elem = {};
elem.style = {};


var a = Anim.create(elem, "key");

a.css({top: 1})
 .css({left: 2});

// ASSERTION: `.start()` is required to start the animation.

scheduler.flush();

eq(elem.style.top, undefined);

// ASSERTION: `.css()` sets properties

a.start();
while (scheduler.runNext() && ! elem.style.top)
    ;

eq(elem.style.top, '1px');
eq(elem.style.left, undefined);
eq(elem._cancel_key, a);     // still busy

scheduler.flush();

eq(elem.style.left, '2px');
eq(elem._cancel_key, undefined);     // no longer busy


// .move()

var stepValue = null;
var stepCount = 0;
function stepFunc(value) {
    if (stepValue != null) {
        assert(value > stepValue);
    }
    stepValue = value;
    ++stepCount;
}

var tStart = scheduler.now();
a = Anim.create(elem, 'key');
a.move(1, 100, stepFunc)
 .start();

scheduler.flush();

// ASSERTION: move displays more than 4 frames for 100-pixel move.
assert(stepCount > 4);

// ASSERTION: move arrives at end value
eq(stepValue, 100);
assert(scheduler.now() >= tStart + 100);

// ASSERTION: .move() to/from NaN completes on first callback
a = Anim.create(elem, 'key');
var vout = undefined;
a.move(1, NaN, function (v) { vout = v; })
 .start();
scheduler.runNext();
assert(vout != vout);


// .delay()

tStart = scheduler.now();
a = Anim.create(elem, 'delay');
a.delay(10000)
 .start();

scheduler.flush();

eq(Math.floor((scheduler.now() - tStart) / 1000), 10);


// TODO: cancel

var cancelPos = 0;
function setCancelPos(pos) {
    cancelPos = pos;
}

elem.style = {};

a = Anim.create(elem, 'cancel')
    .delay(10)
    .css({top: 1})
    .move(1, 100, setCancelPos)
    .css({left: 2})
    .start();

scheduler.runNext();
eq(elem.style.top, undefined);
eq(elem.style.left, undefined);

var tCancel = scheduler.now();
var a2 = Anim.create(elem, 'cancel').start();

eq(tCancel, scheduler.now());
eq(a.tasks[a.nextTask], undefined);
eq(elem.style.top, '1px');
eq(elem.style.left, '2px');
eq(cancelPos, 100);

scheduler.runNext();
scheduler.runNext();

// addTransition

var rule = {
    names: [ 'aspectRatio', 'color' ],
    values: [1, 'black']
};

Anim.addTransition(1, rule);
eq(rule.names.length, 3);
eq(rule.values.length, 3);
eq(rule.names[2], 'transition');
eq(rule.values[2], '-webkit-aspect-ratio 1ms,color 1ms');

