var expect = require('expect.js');
var OWeb = require('oweb.js');
var xhttp = require('xhttp_emu.js');
var scheduler = require('scheduler_emu.js');

var eq = expect.eq;
var assert = expect.assert;

// pending[] is an array of pending (harnessed) HTTP transactions
var pending = xhttp.pending;


var oweb = OWeb.create(xhttp, scheduler, "/observe");
var a = oweb.observe('A');

// Assertion: Creation of a WebOb does not trigger network operations.

eq(a.getValue(), undefined);
eq(pending.length, 0);


// Assertion: Subscribing triggers a transaction, after an asynch callback.

var observer = {
    valid: true,
    invalidate: function () { this.valid = false; },
    activate: function (ob) { ob.subscribe(this); ob.getValue(); },
    deactivate: function (ob) { ob.unsubscribe(this); }
};
observer.activate(a);

eq(a.valid, true);
eq(undefined, a.getValue());
eq(observer.valid, true);

eq(pending.length, 0);
scheduler.flush();   // call oweb's asynch callbacks
eq(pending.length, 1);
eq(pending[0].req.method, 'POLL');
eq(pending[0].req.uri, '/observe');
eq(JSON.parse(pending[0].req.body),
   {add:["A"]});


// Assertion: A second subscription cancels the previous transaction
//    (asynchronously) and starts a new one.

var xhrPrev = pending[0];
var b = oweb.observe('B');
observer.activate(b);
scheduler.flush();  // call oweb's asynch callbacks

eq(xhrPrev.readyState, 5);  // 5 => canceled
eq(pending.length, 1);        // one new transaction
eq(JSON.parse(pending[0].req.body),
   {add:["A","B"]} );


// Assertion: Unsubscribe followed immediately by subscribe does not cancel
//    and restart transaction.

xhrPrev = pending[0];
observer.deactivate(b);
observer.activate(b);
scheduler.flush();
eq(pending, [xhrPrev]);

// Assertion: When a response delivers a new value:
//    - The appropriate observer is notified.
//    - The appropriate observable's value and version are updated

eq(observer.valid, true);
xhrPrev = pending[0];
pending[0].respond(200, '{"id":1, "values": {"A":12, "B": 34} }');

eq(a.valid, false);
eq(b.valid, false);
eq(observer.valid, false);
eq(a.getValue(), 12);
eq(b.getValue(), 34);
eq(oweb.pollID, 1);

// Assertion: New response is automatically sent, but only after asynch callback.
// Assertion: New response reflects updated version.

eq(pending.length, 0);
scheduler.flush();
eq(pending.length, 1);
assert(xhrPrev !== pending[0]);
eq(JSON.parse(pending[0].req.body),
   {id:1});


// Assertion: A second WebOb with an entity name already subscribed does not
// affect the ongoing transaction.

xhrPrev = pending[0];
var bb = oweb.observe('B');
observer.activate(bb);
eq(bb.getValue(), 34);

scheduler.flush();
eq(pending, [xhrPrev]);

// Assertion: A response for a single name notifies only the observables with the same name.

eq(a.valid, true);
eq(b.valid, true);
eq(bb.valid, true);
pending[0].respond(200, '{"id":2, "values": { "B": 99} }');
scheduler.flush();
eq(a.valid, true);
eq(b.valid, false);
eq(bb.valid, false);

// Assertion: Unsubscribing cancels and re-issues new request.

observer.deactivate(a);
scheduler.flush();
eq(pending.length, 1);
eq(JSON.parse(pending[0].req.body),
   {id:2, remove:["A"]});

// Assertion: Unsubscribing an observable has no effect unless it's the last
// one watching a name.

xhrPrev = pending[0];
observer.deactivate(bb);
scheduler.flush();
eq(pending, [xhrPrev]);

// Assertion: Last unsubscribe causes the serve to be updated.

observer.deactivate(b);
scheduler.flush();
eq(pending.length, 1);
eq(JSON.parse(pending[0].req.body),
   {id:2, remove:["A","B"]});


// Assertion: After server acknowledges remove, no new transaction is initiated.

pending[0].respond(200, '{"values":[]}');
scheduler.flush();
eq(pending.length, 0);


//----------------------------------------------------------------

// Assertion: Test Fetch object creation & getValue()

var fo = oweb.fetch({ uri:"/uri", query: {a: 'b'}});
eq(fo.req.uri, '/uri');
eq(fo.getValue(), undefined);


// Assertion: fetch objects begin when subscribed

eq(pending.length, 0);
observer.valid = true;
observer.activate(fo);
eq(pending.length, 1);
eq(pending[0].req.uri, '/uri?a=b');
eq(observer.valid, true);


// Assertion: Repsonse results in invalidation and updates value.

pending[0].respond(200, 'hello');
eq(observer.valid, false);
var v = fo.getValue();
eq(v, 'hello');


// TODO: Clarify behavior on HTTP errors.
