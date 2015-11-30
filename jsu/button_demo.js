var Button = require('button.js');
var demo = require('demo.js');

demo.init({ background: '#ddd', height: 30 });

demo.note(
    'Buttons should have a tooltip.',
    'Each click appends the index of the button to the log element.',
    'Click should work with mouseup and/or mousedown inside element but not on the text');

var texts = [
    ">",
    "+",
    "\u2297",
    "\u21bb",
    "\u25b6",
    "\u21e3",
    "\u21e2",
    "\u21e0"
];

function onClick(id) {
    demo.log({display: 'inline'}, id);
}

var buttons = texts.map(function (content, ndx) {
    return Button.create(content, {
        $onclick: onClick,
        $clickArg: ndx,
        $title: 'Button #' + ndx});
});

demo.append(buttons);


var buttonIndex = 0;
function nextButton() {
    return buttons[ buttonIndex++ % buttons.length];
}

demo.addButton('Enable', function () {
    nextButton().enable(true);
});

demo.addButton('Disable', function () {
    nextButton().enable(false);
});

demo.addButton('Flash', function () {
    nextButton().flash();
});
