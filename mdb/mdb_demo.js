'use strict';

var demo = require('demo.js');
var mdb = require('mdb.js');
var View = require('view.js');
var O = require('observable.js');


demo.init({
    font: '14px Menlo, Courier, monospace'
});


var obs = ['mode', 'stack', 'fetchLocals(1)', 'breakpoints', 'console'];

var table = View.subclass({ $tag: 'table' });
var tr = View.subclass({ $tag: 'tr' });
var th = View.subclass({
    $tag: 'th', textAlign: 'right', padding: '2px 8px', verticalAlign: 'top'
});
var td = View.subclass({ $tag: 'td', color: 'rgb(2,155,81)' });

demo.append(
    table.create(obs.map(function (name) {
        var value = mdb[name];
        if (!value) {
            var m = name.match(/^(\w+)\((.*)\)/);
            value = mdb[m[1]](m[2]);
        }
        return tr.create( th.create(name),
                          td.create(demo.value(value)) );
    }))
);

var tableID = O.slot(1);
var tablePairs = O.func(function (id, fetch) { return fetch(id); },
                        tableID, mdb.fetchTablePairs);

demo.append(
    tr.create( th.create('table ', demo.value(tableID)),
               td.create(demo.value(tablePairs)) )
);


var actions = ['restart', 'go', 'stepOver', 'stepIn', 'stepOut'];
actions.forEach(function (name) {
    demo.addButton(name, mdb.action.bind(mdb, name));
});


demo.addButton('++id', function () { tableID.setValue( tableID.getValue() + 1 ); });
demo.addButton('--id', function () { tableID.setValue( tableID.getValue() - 1 ); });


demo.note(
    [
        View.create({$tag: 'tt', fontWeight: 'bold'},
                    'make run_mdb serve=mdb_demo'),
        ' (this file must be loaded via the server)'
    ]
);

// `demo` and `require` are already available
window.mdb = mdb;
