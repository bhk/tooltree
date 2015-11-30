require('dom_emu.js');
var ConsoleView = require('consoleview.js');
var mdb = require('mdb_emu.js');
var expect = require("expect.js");

function vc(str) {
    return '<' + str + '>';
}

expect.eq(
    ConsoleView.markValues("a!0b!2table 12!1def", vc),
    ['a!b', '<table 12>', 'def']
);

ConsoleView.create(mdb);
