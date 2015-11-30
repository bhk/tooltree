// harness version of scheduler.js

var timeouts = [];
var tNow = 0;
var ndxNext = 0;  // next one to run
var nextID = 0;

function insertTask(type, delay, cb) {
    var task = {
        type: type,
        time: tNow + delay,
        cb: cb,
        id: ++nextID
    };
    var ndx;

    for (ndx = ndxNext; ndx < timeouts.length; ++ndx) {
        if (timeouts[ndx].time > task.time) {
            break;
        }
    }
    timeouts.splice(ndx, 0, task);
    return task.id;
};


exports.now = function () {
    return tNow;
};

exports.delay = function (fn, delay) {
    if (delay == null) {
        delay = 16;
    }
    return insertTask("delay", delay, fn);
};

exports.cancel = function (id) {
    for (ndx = 0; ndx < timeouts.length; ++ndx) {
        if (timeouts[ndx].id == id) {
            timeouts.splice(ndx, 1);
            return;
        }
    }
};


//----------------------------------------------------------------
// Testing APIs
//----------------------------------------------------------------

exports.runNext = function () {
    if (ndxNext < timeouts.length) {
        var ndx = ndxNext++;
        var t = timeouts[ndx];
        timeouts[ndx] = null;
        tNow = t.time;
        t.cb();
        return t.type;
    }
    return null;
};


exports.flush = function () {
    while (exports.runNext())
        ;
};
