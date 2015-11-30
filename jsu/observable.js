// simplified observable API
'use strict';

var Class = require('class.js');
var memoize = require('memoize.js');

var nextUID = 0;
var slice = [].slice;


//--------------------------------
// Observable
//--------------------------------


var Observable = Class.subclass();


Observable.initialize = function () {
    this.value = undefined;
    this.valid = false;
    this.subs = [];
    this.uid = String(nextUID++);
};


Observable.subscribe = function (o) {
    if (this.subs.push(o) == 1) {
        this.onOff(true);
    }
};


Observable.unsubscribe = function (o) {
    var ndx = this.subs.indexOf(o);
    if (ndx < 0) {
        throw new Error('non-subscribed object unsubscribed');
    }
    this.subs.splice(ndx, 1);
    if (this.subs.length == 0) {
        this.onOff(false);
    }
};


// This method is provided for subclasses to override. It will be called
// when number of subscribers transitions to/from 0.
Observable.onOff = function ( /*isActive*/ ) {
    // nothing to do (nothing to watch)
};


// Observable.valid === true:
//    One or more subscribers have obtained the value since it was last
//    modified.  Propagate invaldation.  Avoid recalc.
//
// Observable.valid === false:
//    Notification has been performed since the last recalc cycle. Do not
//    propagate invalidation.  Recalc when `getValue` is called.
//
// Observable.valid === null:
//    Invalidate is being performed.

Observable.invalidate = function () {
    if (this.valid) {
        this.valid = null;
        for (var ndx = this.subs.length; --ndx >= 0;) {
            this.subs[ndx].invalidate(this);
        }
        this.valid = false;
    }
};


//--------------------------------
// Slot
//--------------------------------


var Slot = Observable.subclass();


Slot.initialize = function (value) {
    Observable.initialize.call(this);
    this.value = value;
    this.valid = true;
};


Slot.getValue = function () {
    if (this.valid !== true) {
        if (this.valid === false) {
            this.valid = true;
        } else {
            throw new Error('getValue called during invalidate');
        }
    }
    return this.value;
};


Slot.setValue = function (value) {
    if (value !== this.value) {
        this.value = value;
        this.invalidate();
    }
};


//--------------------------------
// Func
//--------------------------------


// Temporary activation for evaluation outside of an update cycle.

var proTempore = {
    obs: [],

    invalidate: function () {},

    activate: function (o) {
        this.obs.push(o);
        o.subscribe(this);
    },

    flush: function () {
        var o;
        while ( (o = this.obs.pop()) ) {
            o.unsubcribe(this);
        }
    }
};



var Func = Observable.subclass();


// Compute lazily.  The first call to `getValue` will compute the value.  The
// Func stays invalid until then.
//
Func.initialize = function (fn, inputs, strict, lazy) {
    Observable.initialize.call(this);
    this.fn = fn;
    this.watching = strict || [];
    this.inputs = inputs;

    var me = this;

    if (lazy) {
        lazy = lazy.map(function (argn) {
            var func = inputs[argn];

            // cache the observable, not the resulting value
            var memoFunc = memoize(function () {
                var o = func.apply(null, arguments);
                if (Observable.hasInstance(o)) {
                    o.subscribe(me);
                    // this == cache entry
                    this.onflush = o.unsubscribe.bind(o, me);
                }
                return o;
            });

            inputs[argn] = function () {
                var o = memoFunc.apply(null, arguments);
                if (Observable.hasInstance(o)) {
                    return o.getValue();
                }
                return o;
            };
            return memoFunc.flush;
        });

        this.flushLazy = function () {
            lazy.forEach(function (flush) {
                flush();
            });
        };
    }
};


// Construct an observable calculation.  "Drop" to a non-observables when
// the result is constant.
//
function func(fn) {
    var inputs = slice.call(arguments, 1);
    var strict;
    var lazy;

    for (var ndx = 0; ndx < inputs.length; ++ndx) {
        var arg = inputs[ndx];
        if (Observable.hasInstance(arg)) {
            strict = strict || [];
            strict.push( {o: arg, n: ndx} );
        } else if (typeof arg == 'function') {
            lazy = lazy || [];
            lazy.push(ndx);
        }
    }

    if (strict || lazy) {
        return Func.create(fn, inputs, strict, lazy);
    }

    // "constant" function
    return fn.apply(null, inputs);
};


// subscribe/unsubscribe to our inputs
//
Func.onOff = function (isOn) {
    // we have been in, or will be in, an unsubscribed state (maybe stale)
    this.valid = false;

    for (var n = 0; n < this.watching.length; ++n) {
        var o = this.watching[n].o;
        if (isOn) {
            o.subscribe(this);
        } else {
            o.unsubscribe(this);
        }
    }

    !isOn && this.flushLazy && this.flushLazy();
};


Func.getValue = function () {
    var valid = this.valid;

    if (!valid) {
        if (valid === null) {
            throw new Error('getValue called during invalidate');
        }
        if (!this.subs.length) {
            proTempore.activate(this);
        }

        // prepare inputs
        for (var ndx = 0; ndx < this.watching.length; ++ndx) {
            var w = this.watching[ndx];
            this.inputs[w.n] = w.o.getValue();
        }

        this.value = this.fn.apply(null, this.inputs);
        this.valid = true;

        // release cache entries that were not accessed just now
        this.flushLazy && this.flushLazy();
    }
    return this.value;
};


//--------------------------------
// Activator
//--------------------------------


function createActivator(sched) {
    var isScheduled = false;
    var pending = {};
    var me = this;

    me.activate = function (o) {
        if (typeof o == 'function') {
            o = func.apply(null, arguments);
        }
        if (!Observable.hasInstance(o)) {
            return null;
        }

        o.subscribe(me);

        // make valid (after subscribing)
        o.getValue();

        return o.unsubscribe.bind(o, me);
    };

    me.invalidate = function (o) {
        if (!o) throw new Error('identify yourself!');

        pending[o.uid] = o;
        if (!isScheduled) {
            isScheduled = true;
            sched(run);
        }
    };

    function run() {
        isScheduled = false;

        var toRun = pending;
        pending = {};

        for (var uid in toRun) {
            toRun[uid].getValue();
        }

        // deactivate temp subs
        proTempore.flush();
    };

    return me;
};

function wrap(o) {
    return function () { return o; };
}


exports.Observable = Observable;
exports.Slot = Slot;
exports.Func = Func;
exports.slot = Slot.create.bind(Slot);
exports.func = func;
exports.wrap = wrap;
exports.createActivator = createActivator;
