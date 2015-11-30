// scheduler.delay(fn, ms) : call `cb` after `ms` milliseconds
//       If `ms` is null, call `cb` at the next animation frame.
// scheduler.cancel() : cancel a callback previously scheduled with delay()
// scheduler.now() : return time (milliseconds relative to some arbitrary fixed point)


exports.delay = function (fn, delay) {
    if (delay == null) {
        if ("requestAnimationFrame" in window) {
            return ['r', window.requestAnimationFrame(fn)];
        }
        delay = 16;
    }

    if (delay <= 0 && "setImmediate" in window) {
        return ['i', window.setImmediate(fn)];
    } else {
        return ['t', window.setTimeout(fn, delay)];
    }
};

exports.cancel = function (id) {
    switch (id[0]) {
        case 'r': window.cancelAnimationFrame(id[1]); break;
        case 'i': window.clearImmediate(id[1]); break;
        case 't': window.clearTimeout(id[1]); break;
    }
};

window.setTimeout.bind(window);
exports.now = Date.now;
