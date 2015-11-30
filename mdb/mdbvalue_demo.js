// mdbvalue_q.js

'use strict';

var MDBValue = require('mdbvalue.js');
var demo = require('demo.js');
var View = require('view.js');
var O = require('observable.js');

var tablePairs = {
    dflt: [
        ['"abc"', '"short string"'],
        ["1", 'table 3'],
        ["2", 'table 4']
    ],

    'table 1': {error='stale'},

    'table 2': [],

    'table 3': [ ['"abc"', '12'],
                 ['"x y"', '"abc"'],
                 ['12', '"def"'],
                 ['true', 'false'],
                 ['"xyz"', 'table 2'],
                 ['table 3', 'table 3'] ],

    'table 4': [
        ['"abc"', 'function 11'],
        ['"def"', '"short string"'],
        ['"this is a longer string longer string longer string longer string longer string longer string longer string"', '123.4'],
        ['table 3', 'table 4']
    ]
};

var mdb = {};

mdb.fetchTablePairs = function (desc) {
    return O.slot({
        done: true,
        data: tablePairs[desc] || tablePairs.dflt
    });
};

mdb.openValue = function (desc) {
    demo.log("open: " + desc);
};

var mv = MDBValue.create(mdb);

demo.init({
    font: '12px Arial, Helvetica'
});


var values = [
    'table 1',
    '123',
    '"hi"',
    'function 1',
    'userdata 1',
    'thread 3',
    'true',
    'nil',
    'table 2',
    'table 3',
    'table 4'
];


demo.append( values.map( function (desc) {
    return View.create(desc + ": ", mv.createValueView(desc), " blah blah");
}));


demo.note(
    'Clicking "table N" should expand/contract the table',
    'table 1 shows an error condition',
    'table 2 is empty',
    'Tooltips should show for "Expand/collapse" and "open in new window" buttons',
    'The "open in new window" button should log the value description'
);
