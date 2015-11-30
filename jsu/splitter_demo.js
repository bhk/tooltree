'use strict';

var View = require('view.js');
var O = require('observable.js');
var Splitter = require('splitter.js');
var demo = require('demo.js');


function box(bg, text, value) {
    return View.create({
        background: bg,
        border: '2px solid rgba(0,0,0,0.1)',
        borderTopColor: 'rgba(255,255,255,0.12)',
        borderLeftColor: 'rgba(255,255,255,0.12)',
        font: '14px Helvetica',
        color: 'rgba(0,0,0,0.5)'
    }, View.create({
        // set padding here so the parent (the split element) can be
        // arbitrarily small (so its borders will look right wen small).
        padding: 12
    }, text, (value && demo.value(value))));
}


demo.init({
    height: 300,
    border: 'none',
    position: 'relative'
});


var sizeA = O.slot('25%');
var sizeB = O.slot('33%');
var sizeC = O.slot('33%');
var sizeD = O.slot(100);    // pixels

// make it easier to detect dragger position
var TSplitter = Splitter.subclass({ $width: 10 });

demo.append(
    TSplitter.create({
        $leftSize: sizeA,
        $left: box('#ccb', 'A = ', sizeA),
        $right: TSplitter.create({
            $topSize: sizeB,
            $top: box('#bbc', 'B = ', sizeB),
            $bottom: TSplitter.create({
                $rightSize: sizeC,
                $right: box('#cbb', 'C = ', sizeC),
                $left: TSplitter.create({
                    $bottomSize: sizeD,
                    $top: box('#bcb'),
                    $bottom: box('#bcc', 'D = ', sizeD)
                })
            })
        })
    })
);


function toggle(a, b) {
    this.setValue( this.getValue() == a ? b : a );
}

demo.addButton('A 0 / 25%', toggle.bind(sizeA, '25%', '0%'));
demo.addButton('B 0 / 33%', toggle.bind(sizeB, '33%', 0));
demo.addButton('C 0 / 33%', toggle.bind(sizeC, '33%', 0));
demo.addButton('D 0 / 100', toggle.bind(sizeD, 100, 0));

demo.note(
    'Borders of the two sub-elements should be visible',
    'Transitions should be animated.',
    'Dragging dividers should be smooth.',
    'Dividers should be centered on the boundary',
    'The bottom-right pair is the only non-resizable splitter',
    'After dragging, a size value should have the same units ("%" or number).'
);


demo.log('A: ', demo.value(sizeA));
demo.log('B: ', demo.value(sizeB));
demo.log('C: ', demo.value(sizeC));
demo.log('D: ', demo.value(sizeD));
