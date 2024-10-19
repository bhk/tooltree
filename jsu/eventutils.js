'use strict';


function listen(elem, evt, fn, useCapture) {
    elem.addEventListener(evt, fn, useCapture);
    return elem.removeEventListener.bind(elem, evt, fn, useCapture);
}


// captureClick: call a handler when an element is clicked.  A "click" is
// defined as a `mouseup` inside of the element when the previous
// `mousedown` was also inside that element.
//
// This avoids some problematic issues with the `click` event:
//
//  * A `click` event is not generated when the mouseup and mousedown occur
//    over different sub-elements of the specified element.
//
//  * Safari and Chrome (but not Firefox) have a bug in `click` handling
//    with floating elements: a click event will not be sent if the
//    mousedown occurs on *text* while the mouseup occurs somewhere else in
//    the element (or vice versa).
//
// We address both of these issues by capturing the next `mouseup` after a
// `mousedown` is detected. If it occurs inside the element, we consider it
// a click.
//
// Inputs:
//   elem: elem to detect clicks on
//   fn: fn to call when clicked
//   thisArg: `this` argument to `fn`
// Returns:
//    dereg: call this function to deregister
//
// Note: evt.preventDefault() on "mousedown" prevents selection (if drag
// extends into selectable elements) on WebKit, which is what we want, but
// it disrupts ':active' handling on Mozilla, so we don't use it.
//
function captureClick(elem, fn, thisArg) {

    function mousedown(evt) {
        var evtDown = evt;
        var dereg = listen(document, 'mouseup', mouseup, false);

        function mouseup(evt) {
            if (elem.contains(evt.target)) {
                fn.call(thisArg, elem, evt, evtDown);
            }
            dereg();
        }
    }

    return listen(elem, 'mousedown', mousedown, true);
}


// A "drag" operation starts with a mousedown in an element and continues
// until the next mouseup (whether inside or outside of that element).  This
// function does not move any document contents, it only tracks the
// "dragging" of the mouse.
//
function captureDrag(elem, fn, thisArg) {
    function onDown(evt) {
        var xDown = evt.pageX;
        var yDown = evt.pageY;

        function drag(evt) {
            var dx = evt.pageX - xDown;
            var dy = evt.pageY - yDown;
            var type = evt.type == 'mousemove' ? 'drag' : 'stop';
            fn.call(thisArg, type, elem, evt, dx, dy);
            if (type == 'stop') {
                deregMove();
                deregUp();
            }
        }
        var deregMove = listen(document, 'mousemove', drag, false);
        var deregUp = listen(document, 'mouseup', drag, false);

        fn.call(thisArg, 'start', elem, evt);
    };

    return listen(elem, 'mousedown', onDown, true);
}



// Keyboard event registration
//
//  - Register a single event handler and dispatch events for different
//    keys to different functions.
//  - Simplify naming of keys.
//  - Simplify de-registration
//  - Simplify preventing default behavior.
//
// Inputs:
//   elem: elem to register on
//   evtType: key event to listen for
//   useCapture: same as parameter to addEventListener
//   handlers: object mapping event names to functions. See code beow for
//      event name construction. Handlers return `false` to indicate that
//      the event was NOT handled.
// Returns:
//    dereg: call this function to deregister
//
function handleKeys(elem, evtType, useCapture, handlers) {
    function on(evt) {
        var name;
        if (evt.type == 'keypress') {
            name = String.fromCharCode(evt.charCode);
        } else {
            name = ( (evt.altKey ? "A_" : "") +
                     (evt.ctrlKey ? "C_" : "") +
                     (evt.metaKey ? "M_" : "") +
                     (evt.shiftKey ? "S_" : "") +
                     (evt.key || "---") );
        }

        var f = handlers[name] || handlers.other;
        if (f) {
            if (f(evt, name) !== false) {
                evt.preventDefault();
                evt.stopPropagation();
            }
        }
    }

    return listen(elem, evtType, on, useCapture);
}


exports.listen = listen;
exports.captureClick = captureClick;
exports.captureDrag = captureDrag;
exports.handleKeys = handleKeys;
