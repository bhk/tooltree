var demo = require('demo.js');
var O = require('observable.js');
var ConsoleView = require('consoleview.js');

var mdb = require('mdb_emu.js');

var cv = ConsoleView.create(mdb);


//----------------------------------------------------------------
// demo view

demo.init({
    height: 164,
    overflow: 'auto'
});

demo.append(cv);

demo.note(
    'ENTER should append a command and response to the console',
    'UP/DOWN should cycle through history',
    'When appended entries fall below the visible area, it should scroll smoothly to expose them'
);
