global.window = global.window || global;

var timeouts = [];
window.setTimeout = function (cb, ms) {
    timeouts.push(cb);
};

window.setTimeout.flush = function () {
    var cb;
    while ( (cb = timeouts.shift()) != undefined) {
        cb();
    }
};
