// Harness implementation of `xhttp` (HTTP transaction factory)

var makeQuery = require('xhttp.js').makeQuery;

// pending xhttp instances: call x.respond(code, data) to complete them.
var pending = [];


function xhttp(req, cb) {
    var me = {};
    if (typeof req == 'string') {
        req = {uri: req};
    }
    req.uri += makeQuery(req.query);
    req.body = req.body || '';
    req.method = req.method || 'get';

    me.req = req;
    me.cb = cb;

    function finish(state) {
        var ndx = pending.indexOf(me);
        pending.splice(ndx, 1);
        me.readyState = state;
    }

    me.readyState = 1;
    me.abort = function () {
        if (me.readyState < 4) {
            finish(5);
        }
    };

    me.respond = function (code, data) {
        finish(4);
        var err = (code >= 200 && code < 300) ? false : code;
        me.responseText = data;
        me.cb(err, (err ? null : data), me);
    };

    pending.push(me);
    return me.abort.bind(me);
}


xhttp.pending = pending;

xhttp.makeQuery = makeQuery;

module.exports = xhttp;
