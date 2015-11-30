var expect = require('expect.js');
var eventutils = require('eventutils.js');

var eq = expect.eq;


// listen

var listen = eventutils.listen;

var e = {
    listeners: [],
    addEventListener: function (evt, fn, cap) {
        this.listeners.push([evt, fn, cap]);
    },
    removeEventListener: function (evt, fn, cap) {
        for (var index in this.listeners) {
            var ll = this.listeners[index];
            if (ll[0] === evt && ll[1] === fn && ll[2] === cap) {
                this.listeners.splice(index, 1);
                return;
            }
        }
        throw new Error('remove of unregistered listener');
    }
};


var f1 = function () {};

var dereg = listen(e, f1, true);
eq(e.listeners.length, 1);

dereg();
eq(e.listeners.length, 0);


