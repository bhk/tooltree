require('dom_emu.js');
var LocalsView = require('localsview.js');

var tablePairs = {
    'table 1': {error: 'stale'},
    'table 2': [],
    'table 3': [ ['"abc"', '12'],
                 ['12', '"def"'] ]
};

var mdb = {};

mdb.openValue = function () {};

var lv = LocalsView.create(mdb, [
    { name: 'a', value: '"this is a test"' },
    { name: 'b', value: '123' }
]);
