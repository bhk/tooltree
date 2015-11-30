'use strict';

var View = require('view.js');
var captureDrag = require('eventutils.js').captureDrag;


function assert(value, str) {
    if (!value) {
        throw new Error('Assertion failed: ' + str);
    }
}


function cap(str) {
    return str[0].toUpperCase() + str.substr(1);
}



//----------------------------------------------------------------

// Split: base class for the splitter itself and its children

var Split = View.subclass({
    $class: 'split',
    overflow: 'hidden',
    position: 'absolute',
    boxSizing: 'border-box',
    userSelect: 'none',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,

    // "T" is set on children except during dragging
    '?.T': {
        transition: 'left,right,height,top,bottom,width'.replace(/,|$/g, ' 150ms$&')
    }
});


var Splitter = Split.subclass();


Splitter.$width = 4;


// `a` and `b` must be View instances.
//
Splitter.postInit = function () {

    // Select top/bottom split vs. left/right split

    var me = this;
    var isVertical = !!me.$left;
    var d, dStyle, deact;

    var top = 'top';
    var height = 'height';
    var bottom = 'bottom';
    if (isVertical) {
        top = 'left';
        height = 'width';
        bottom = 'right';
    }

    var a = me['$' + top];
    var b = me['$' + bottom];
    assert(a, 'Splitter: no $left or $top');
    assert(b, 'Splitter: no $right/$bottom to match $left/$top');
    var aStyle = a.e.style;
    var bStyle = b.e.style;

    // Select "top" or "bottom" child to apply `size` to

    var fromTop = me['$' + top + 'Size'];
    var size, sizeA, sizeB, sizeD;
    if (fromTop) {
        sizeA = height;
        aStyle[bottom] = 'auto';
        sizeB = top;
        sizeD = top;
    } else {
        sizeA = bottom;
        bStyle[top] = 'auto';
        sizeB = height;
        sizeD = bottom;
    }
    size = me['$' + sizeD + 'Size'];
    assert(size != null, 'Splitter: no $[top/left/bottom/right]Size');

    // Normally we subscribe to `size` and enable transitions, but during
    // dragging we disable transitions and call setSize() synchronously.

    function setSize(value) {
        if (!isNaN(value)) {
            value += 'px';
        }
        aStyle[sizeA] = value;
        bStyle[sizeB] = value;
        if (d) {
            dStyle[sizeD] = value;
        }
    }

    function watchSize(isOn) {
        a.enableClass('T', isOn);
        b.enableClass('T', isOn);
        if (isOn) {
            deact = me.activate(setSize, size);
        } else {
            deact();
        }
    };

    if (size instanceof Object && size.setValue) {

        // Draggable divider

        d = Split.create({
            transition: 'none',
            cursor: isVertical ? 'col-resize' : 'row-resize'
        });
        dStyle = d.e.style;

        var w = me.$width;
        // use negative margin to center the divider on the boundary
        var margin = - w/2;

        dStyle[height] = w + 'px';
        dStyle[fromTop ? bottom : top] = 'auto';
        dStyle['margin' + cap(sizeD)] = margin + 'px';

        var startOffset, isPct;

        var doDrag = function(type, elem, evt, dx, dy) {
            if (type == 'start') {
                // offset[Top/Left/...] gives edge of *padding* rectangle
                startOffset = d.e['offset' + cap(top)] - margin;
                isPct = /%$/.test(aStyle[sizeA]);
                watchSize(false);
            } else {
                var total = me.e['offset' + cap(height)];
                var pos = startOffset + (isVertical ? dx : dy);
                pos = (pos > total ? total :
                       pos >= 0    ? pos :
                       0);
                var newSize = (fromTop ? pos : total - pos);
                if (isPct) {
                    newSize = (newSize * 100 / total) + '%';
                }

                size.setValue(newSize);

                if (type == 'stop') {
                    watchSize(true);
                } else {
                    setSize(newSize);
                }
            }
            evt.preventDefault();
        };
        captureDrag(d.e, doDrag);
    }

    // attach positioning style information
    a.enableClass(Split.className);
    b.enableClass(Split.className);
    watchSize(true);

    me.append(a, b, d);
};


module.exports = Splitter;
