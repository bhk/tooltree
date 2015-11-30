'use strict';

var O = require('observable.js');
var expect = require('expect.js');
var eq = expect.eq;


//----------------------------------------------------------------
// Mock scheduler
//----------------------------------------------------------------

var callbacks = [];

function sched(cb) {
    callbacks.push(cb);
}

sched.isPending = function () {
    return callbacks.length > 0;
};

sched.call = function () {
    var cb = callbacks.shift();
    cb && cb();
};

sched.flush = function () {
    while (sched.isPending())
        sched.call();
};

var act = O.createActivator(sched);


//----------------------------------------------------------------


// Assertion: Activator.activate(fn, args...) constructs O.Func, subscribes,
//     and calls it.

var ov = O.slot(1);
var count = 0;
var dereg = act.activate(function (a) { count += a; }, ov);
eq(1, count);
eq(false, sched.isPending());

// Assertion: Slot invalidates when valid and changed

ov.setValue(7);
eq(true, sched.isPending());
sched.flush();
eq(8, count);

// Assertion: Slot does NOT invalidate subscribed listeners when not changed

ov.setValue(7);
eq(false, sched.isPending());

// Assertion: Activator.deactivate() unsubscribes to the deactivated object.
// Assertion: Slot does NOT invalidate unsubscribed listener

dereg();
ov.setValue(1);
eq(false, sched.isPending());


// Assertion: Slot does NOT invalidate subscribed listener when already invalid

dereg = act.activate(function (a) { count += a; }, ov);
sched.flush();
eq(true, ov.valid);
ov.valid = false;
ov.setValue(99);
eq(false, sched.isPending());


(function (){
     // Assertion: Func calculates value appropriately, getting values from
     //    observable arguments and using other arguments literally.

     var oa = O.slot(1);
     var f = O.func(function (a, b) { return a+b; }, oa, 2);

     var k = 0;
     var dereg = act.activate(function (v) {
                                   k= v;
                              }, f);
     eq(3, k);

     oa.setValue(3);
     eq(3, k);

     // Assertion: Func subscribes to its inputs when it becomes subscribed

     sched.flush();
     eq(5, k);

     // Assertion: func recognizes constant values

     var f2 = O.func(function (a,b) { return a + b; }, 1, 2);
     eq(3, f2);

}());


// Assertion: Activator.activate(observable) subscribes to the observable.
(function (){
     var ov = O.slot(1);
     var dereg = act.activate(ov);
     eq(1, ov.subs.length);
     dereg();
     eq(0, ov.subs.length);
}());


//----------------------------------------------------------------
// `func` values with lazy and static dependencies
//----------------------------------------------------------------

(function (){

     var oa = O.slot(false);
     var ob = O.slot('b');
     var fValue = 0;
     var fbCount = 0;
     var f = O.func(function (a, fb, bArg) { return (fValue = (a && fb(a))); },
                    oa,
                    function (arg) {
                        ++fbCount;
                        return (typeof arg == 'number') ? arg : ob;
                    });

     // Assertion: Activation computes the initial value.
     var actCount = 0;
     var dereg = act.activate(function () { ++actCount; }, f);
     eq(false, fValue);
     eq(fValue, f.getValue());
     eq(1, actCount);

     // Assertion: When a static dependency is modified, an update is triggered.
     oa.setValue(0);
     sched.flush();
     eq(0, fValue);
     eq(fValue, f.getValue());
     eq(2, actCount);

     // Assertion: When an UNUSED lazy dependency is invalidated, NO update
     // is triggered.
     ob.setValue('OB');
     sched.flush();
     eq(2, actCount);

     // Assertion: When an lazy dependency is accessed and returns a raw value,
     // the raw function receives that value.
     oa.setValue(1);
     sched.flush();
     eq(1, fValue);
     eq(fValue, f.getValue());
     eq(3, actCount);
     eq(1, fbCount);

     // Assertion: When an lazy dependency is accessed and returns an observable,
     // the raw function receives the extracted value.
     oa.setValue('x');
     sched.flush();
     eq('OB', fValue);
     eq(4, actCount);
     eq(2, fbCount);

     // Assertion: The returned observable is subscribed to, and the
     // observable (not its value) is cached.
     var obOld = ob;
     ob = O.slot('OBNew');

     obOld.setValue('OB2');
     sched.flush();
     eq('OB2', fValue);
     eq(2, fbCount);    // no additional calls to fb()


     // Assertion: Calling the thunk with different args discards the cached
     // observable.
     oa.setValue('y');
     sched.flush();
     eq('OBNew', fValue);
     eq(3, fbCount);

     actCount = 0;
     obOld.setValue('-');
     sched.flush();
     eq(0, actCount);

     ob.setValue('xx');
     sched.flush();
     eq('xx', fValue);
     eq(1, ob.subs.length);

     // Assertion: Func unsubscribes from strict AND lazy dependencies when
     // it becomes unsubscribed.

     dereg();
     eq(0, ob.subs.length);
     eq(0, oa.subs.length);

}());
