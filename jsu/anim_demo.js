var scheduler = require('scheduler.js');
var Anim = require('anim.js').newClass(scheduler);
var demo = require('demo.js');
var View = require('view.js');


var A = 15, B = 115, W = 32;


demo.init({ height: B+A+W, position: 'relative' });

demo.note(
    "Animation should begin and end with a background color \"flash\"",
    "'Cancel' should fast-forward to bottom-left, gray border state.",
    "'New' or 'Start' should cancel any running animation and restart.",
    "Restarted animations should look exactly the same (start at left with gray border)."
);

var box = View.create({
    boxSizing: 'border',
    border: '3px solid #aaa',
    width: W,
    height: W,
    position: 'absolute',
    left: A,
    top: A,
    borderRadius: 5
});

demo.append(box);

var a;

function doNew() {
    var mid = (A+B)/2;

    function setLeft(pos) { box.e.style.left = pos + 'px'; }
    function setTop(pos) { box.e.style.top = pos + 'px'; }

    a = Anim.create(box.e, 'demo');
    a.css({backgroundColor: 'black', top: A})
        .cssTransition({backgroundColor: 'white'}, 500)
        .css({ borderColor: 'red' })
        .move(A, mid, setLeft)
        .move(A, mid, setTop)
        .move(mid, B, setLeft)
        .move(mid, B, setTop)
        .delay(200)
        .move(B, mid, setLeft)
        .move(B, mid, setTop)
        .move(mid, A, setLeft)
        .css({backgroundColor: 'black', transition: 'none'})
        .cssTransition({backgroundColor: 'white'}, 500)
        .css({transition: 'none', borderColor: '#888' })
        .start();
}


function doStart() {
    if (a) {
        a.start();
    } else {
        demo.log('Animation not yet created!');
    }
}


function doCancel() {
    a.cancel();
}


demo.addButton('New', doNew);
demo.addButton('Start', doStart);
demo.addButton('Cancel', doCancel);
