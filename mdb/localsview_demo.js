var demo = require('demo.js');
var LocalsView = require('localsview.js');
var O = require('observable.js');
var mdb = require('mdb_emu.js');


var sampleLocals = [
    { name: 'a', value: '"this is a test"' },
    { name: 'b', value: '123' },
    { name: 'c', value: 'true' },
    { name: 'd', value: 'false' },
    { name: 'long_variable_name', value: '"this is a test"' },
    { name: 'e', value: 'table 3' },
    { name: 'f', value: 'function 4' },
    { name: 'g', value: 'userdata 5' },
    { name: 'h', value: 'thread 6' }
];


var content = O.slot();

demo.init({
    height: 164,
    width: '50%',
    overflow: 'scroll'
});

demo.append(
    LocalsView.create(mdb, content)
);

demo.addButton('Null', content.setValue.bind(content, null));
demo.addButton('Fill', content.setValue.bind(content, sampleLocals));
demo.addButton('Error', content.setValue.bind(content, 'Error loading variables'));
