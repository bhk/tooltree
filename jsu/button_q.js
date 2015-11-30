var expect = require('expect.js');
require('dom_emu.js');
var Button = require('button.js');

var btn = Button.create({
    $onclick: onClick,
    $clickArg: 'btnid',
    $title: 'Tooltip'
}, '>');


expect.eq(btn.$onclick, onClick);
expect.eq(btn.$clickArg, 'btnid');

var clicked = false;
function onClick() {
    clicked = true;
}

// simulate click
btn.$onclick();

expect.eq(true, clicked);
