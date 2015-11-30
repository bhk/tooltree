// Anim: animator class; see anim.txt

"use strict";

var View = require('view.js');


// tween: [0...1] --> [0...1]
function tween(n) {
    return Math.sin(Math.PI/2 * n);
}


// Add a 'transition' CSS property naming all the properties already in the
// rule.
function addTransition(delayMS, rule) {
    var props = [];
    rule.names.forEach(function (name) {
        props.push(View.cssName(name) + ' ' + delayMS + 'ms');
    });
    rule.names.push(View.normalizeName('transition'));
    rule.values.push(props.join(','));
}


var Anim = require("class.js").subclass();

// see scheduler.js
Anim.newClass = function (scheduler) {
    var c = this.subclass();
    c.scheduler = scheduler;
    return c;
};


Anim.initialize = function (elem, key) {
    this.e = elem;
    this.key = "_cancel_" + (key || 'anim');
    this.tasks = [];
    this.nextTask = 0;
    this.thisStep = this.step.bind(this);
    this.pending = false;
};


Anim.start = function () {
    if (this.e[this.key]) {
        this.e[this.key].cancel();
    }
    this.e[this.key] = this;
    this.nextTask = 0;

    this.schedule(0);
    return this;
};


Anim.schedule = function (delay) {
    if (this.pending) {
        this.scheduler.cancel(this.pending);
    }
    this.pending = this.scheduler.delay(this.thisStep, delay);
};


Anim.cancel = function () {
    // A pending callback might cause cancel to be called twice.
    if (this.e[this.key] !== this) {
        return;
    }

    // Process all remaining tasks without delay. For `move` tasks, call
    // callback exactly once with final value.
    while (this.doTask(true) != "done")
        ;
    this.e[this.key] = undefined;
};


// nominal duration for a move operation
Anim.MOVE_DURATION = 200;

// distance below which the duration decreases
Anim.MOVE_SHORT = 32;


// Perform task and return delay to the next task
//
Anim.doTask = function (noDelay) {
    var task = this.tasks[this.nextTask++];
    if (!task) {
        return "done";
    }

    switch (task[0]) {
    case "delay":
        return task[1];

    case "css":
        var rules = task[1];
        View.applyRulesToElement(rules, this.e, task[2]);
        // We need to wait for CSS properties to take effect before we
        // process another 'css' record, otherwise transition-based animations
        // will be skipped.  I've found that requestAnimationFrame does not
        // allow for this, but a 16ms setTimeout does (on Chrome)
        return 17 + task[3];

    case "move":
        var start = task[1];
        var stop = task[2];
        var fn = task[3];

        if (this.t0 == undefined) {
            this.t0 = this.scheduler.now() - 16;  // start at first iter
        }

        var range = Math.abs(stop - start);
        var tTotal = this.MOVE_DURATION * Math.min(1, range/this.MOVE_SHORT);
        var duration = this.scheduler.now() - this.t0;
        var frac = tween(Math.min(1, duration / tTotal));
        var pos = start + Math.floor(frac * (stop - start) + 0.5);
        if (noDelay || Math.abs(pos - stop) < 1 || pos != pos) {
            pos = stop;
            this.t0 = undefined;
        } else {
            --this.nextTask;
        }
        fn(pos);
    }
    return null;
};


Anim.step = function () {
    this.pending = false;
    var delay = this.doTask();
    if (delay == "done") {
        this.cancel();
    } else {
        this.schedule(delay);
    }
};


Anim.css = function (props) {
    return this.cssTransition(props, 0);
};


Anim.cssTransition = function (props, delayMS) {
    var obj = {};
    var rules = [];
    View.scanProps(props, obj, rules, '');
    if (delayMS == null) {
        delayMS = 0;
    }
    if (delayMS > 0) {
        rules.forEach(addTransition.bind(null, delayMS));
    }
    this.tasks.push( ['css', rules, obj.$id, delayMS] );
    return this;
};


["delay", "move"].forEach(function (name) {
    Anim[name] = function (a, b, c) {
        this.tasks.push( [name, a, b, c] );
        return this;
    };
});


// for testing
Anim.addTransition = addTransition;

module.exports = Anim;
