var Bubble = require('bubble.js');
var demo = require('demo.js');
var O = require('observable.js');
var View = require('view.js');

demo.init({ padding: 10 });


var oc = O.slot();

demo.append(
    Bubble.create({
        $caption: 'bubbleA',
        $content: oc
    })
);

var full = View.create(
    View.create("Line 1"),
    View.create("Line 2"),
    View.create("Line 3")
);


demo.addButton('Fill', function () { oc.setValue(full); });

demo.addButton('Empty', function () { oc.setValue(null); });
