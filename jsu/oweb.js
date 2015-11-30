// Observable Web
// See oweb.txt.

'use strict';

var Class = require('class.js');
var O = require('observable.js');


//----------------------------------------------------------------
// Use `Slot` but don't expose `setValue`

var Ob = O.Slot.subclass();
Ob.update = Ob.setValue;
Ob.setValue = null;


//----------------------------------------------------------------
// FetchOb: a remote observable object
//
// value = when incomplete: {}
//         when complete:   { done, data, xhr }
//    done: "ok" | "error"
//    data: String | null
//    xhr: xhr object
//

var FetchOb = Ob.subclass();

FetchOb.initialize = function (req, xhttp) {
    O.Slot.initialize.call(this);
    this.req = req;
    this.xhttp = xhttp;
};


FetchOb.onOff = function (isOn) {
    if (isOn) {
        this.cancel = this.xhttp(this.req, FetchOB_complete.bind(this));
    } else if (this.cancel) {
        this.cancel();
    }
};


function FetchOB_complete(err, data, xhr) {
    this.cancel = null;
    this.update(err
                ? { error: err }
                : data);
}


//----------------------------------------------------------------
// WebOb: a remote observable object

var WebOb = O.Observable.subclass();


WebOb.initialize = function (oweb, name) {
    O.Observable.initialize.call(this, undefined);
    this.oweb = oweb;
    this.name = name;
};


WebOb.getValue = function () {
    this.valid = true;
    return this.oweb.values[this.name];
};


WebOb.onOff = function (isOn) {
    this.valid = false;
    this.oweb.addRemoveOb(this, isOn);
};


//----------------------------------------------------------------

var OWeb = Class.subclass();


OWeb.initialize = function (xhttp, scheduler, uri) {
    this.xhttp = xhttp;
    this.scheduler = scheduler;
    this.uri = uri;
    this.updatePending = false;
    this.cancel = null;
    this.sentBody = '';
    this.sentRemoves = [];

    // uid -> WebObs [currently subscribed ones]
    this.obs = Object.create(null);

    this.pollID = undefined;   // ID of last response
    this.values = Object.create(null);    // name -> value (as of last response)
};


OWeb.fetch = function (req) {
    return FetchOb.create(req, this.xhttp);
};


OWeb.observe = function (name) {
    return WebOb.create(this, name);
};


OWeb.addRemoveOb = function (wob, isOn) {
    if (isOn) {
        this.obs[wob.uid] = wob;
    } else {
        delete this.obs[wob.uid];
    }
    this.update();
};


OWeb.update = function () {
    // cancel & start transactions asynchronously, since many
    // subscribe/unsubscribe operations can happen synchronously.
    if (! this.updatePending ) {
        this.updatePending = true;
        this.scheduler.delay(this.updateCB.bind(this), 0);
    }
};


OWeb.updateCB = function () {
    this.updatePending = false;

    // Update new (and old) WebObs.  Make note of newly- and
    // currently-subscribed names.

    var add = [];
    var nameIsWatched = {};
    for (var uid in this.obs) {
        var wob = this.obs[uid];
        var name = wob.name;
        var value = this.values[name];

        nameIsWatched[name] = true;

        // `undefined` is not a JSON value
        if (value === undefined) {
            add.push(name);
        }
    }

    // Find names no longer subscribed

    var remove = [];
    for (var name in this.values) {
        if (! nameIsWatched[name]) {
            remove.push(name);
        }
    }

    // construct request

    var body = JSON.stringify({
        id: this.pollID,
        add: (add.length ? add : undefined),
        remove: (remove.length ? remove : undefined)
    });

    if (this.cancel) {
        if (body === this.sentBody) {
            // nothing to change
            return;
        }

        // cancel pending request
        this.cancel();
        this.cancel = null;
    }

    this.sentBody = body;
    this.sentRemove = remove;

    if (this.pollID === undefined && add.length == 0) {
        // nothing to wait on, nothing to remove
        return;
    }

    this.cancel = this.xhttp({ method: 'POLL', uri: this.uri, body: body },
                             OWeb_handleResponse.bind(this));
};


function OWeb_handleResponse(error, data) {
    this.cancel = null;

    var resp = data && JSON.parse(data);

    // parse response and notify corresponding objects
    if (! (resp instanceof Object)) {
        // TODO
        return;
    }
    var respValues = resp.values || Object.create(null);

    // Process response

    this.pollID = resp.id;

    this.sentRemove.forEach(function (name) {
        delete this.values[name];
    }.bind(this));

    for (var name in respValues) {
        this.values[name] = respValues[name];
    }

    for (var uid in this.obs) {
        var wob = this.obs[uid];
        if (wob.name in respValues) {
            wob.invalidate();
        }
    }

    this.update();
}


module.exports = OWeb;
