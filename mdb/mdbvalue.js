// mdbvalue.js : construct views for Lua data values
//
// Usage:
//
//   mv = MDBValue.create(mdb);
//   view = mv.createValueView(desc);
//

'use strict';

var View = require('view.js');
var O = require('observable.js');
var Class = require('class.js');
var Bubble = require('bubble.js');
var Button = require('button.js');


function ttView(props) {
    return View.subclass({
        $class: 'lua-syntax',
        $tag: 'span',
        font: '12px Menlo, Monaco, monospace'
    }, props);
}

var syntaxViews = {
    keyword: ttView({ color: '#6175B3', fontWeight: 'bold' }),
    number:  ttView({ color: '#925200', fontWeight: 'bold' }),
    string:  ttView({ color: '#079947', fontWeight: 'bold' }),
    comment: ttView({ color: '#5F8B88', fontStyle: 'italic'}),
    id:      ttView()
};


var InfoView = View.subclass({
    $class: 'info',
    font: '12px "Helvetica", sans-serif',
    color: '#999',
    fontStyle: 'italic',
    margin: '0 8px'
});


var ErrorView = InfoView.subclass({
    $class: 'error',
    color: '#b00'
});


var Table = ttView({
    $class: 'lua-table',
    $tag: 'table',
    borderSpacing: '4px 2px',
    userSelect: 'auto'
});


var TableRow = View.subclass({
    $tag: 'tr'
});


var TableKey = View.subclass({
    $class: 'table-key',
    $tag: 'td',
    display: 'table-cell',
    position: 'relative',
    textAlign: 'right',
    verticalAlign: 'top'
});


var TableValue = View.subclass({
    $class: 'table-value',
    $tag: 'td',
    borderCollapse: 'collapse',
    content: 'close-quote',
    verticalAlign: 'top',
    textAlign: 'left',
    paddingLeft: 4,
    '?::before': {
        content: '"= "',
        color: '#999',
        verticalAlign: 'top'
    }
});


var TextButton = Button.subclass({
    fontSize: 12,
    fontFamily: 'Menlo, Monaco, monospace',
    cssFloat: 'none',
    display: 'inline',
    padding: '0 2px',
    lineHeight: 0,
    fontWeight: 'normal',
    margin: 0,
    borderRadius: 5,
    textShadow: 'none'
});


var MDBValue = Class.subclass();


MDBValue.initialize = function (mdb) {
    this.mdb = mdb;
};


MDBValue.makeTableRow = function (pair) {
    var key = pair[0];
    var value = pair[1];

    var id = key.match(/^"([A-Za-z_][\w_]*)"$/);

    var lhs = (id ? syntaxViews.id.create(id[1]) :
               ['[', this.createValueView(key), ']']);

    return TableRow.create(
        TableKey.create(lhs),
        TableValue.create(this.createValueView(value))
    );
};


var errorDescs = {
    stale: 'Reference has expired',
    dflt: 'Unknown error'
};


MDBValue.createTableView = function (desc, isOpen) {
    var isShown = O.slot(isOpen);

    var toggle = function () {
        isShown.setValue( !isShown.getValue() );
    };

    var caption = [
        TextButton.create(desc, {
            $onclick: toggle,
            $title: 'Expand/collapse'
        }),
        TextButton.create('\u22a1', {
            $onclick: this.mdb.openValue.bind(this.mdb, desc),
            $title: 'Open in new window'
        })
    ];

    var content = O.func(function (isShown, fetchPairs) {
        if (!isShown) {
            return null;
        }

        var pairs = fetchPairs(desc);
        var errorText = pairs instanceof Object && errorDescs[pairs.error]
            || errorDescs.dflt;

        return !pairs ? InfoView.create('Loading...') :
            !(pairs instanceof Array) ? ErrorView.create(errorText) :
            pairs.length == 0 ? InfoView.create('empty') :
            Table.create( pairs.map(this.makeTableRow.bind(this)) );

    }.bind(this), isShown, this.mdb.fetchTablePairs);

    return Bubble.create({
        $caption: caption,
        $content: content
    });
};


// Return Lua type, given an MDB Value Description
//
MDBValue.descToType = function (desc) {
    return ( /^"/.test(desc) ? 'string' :
             /^-?\d/.test(desc) ? 'number' :
             /^(true|false)$/.test(desc) ? 'boolean' :
             // nil, table, function userdata, thread
             desc.match(/^[a-z]*/)[0] );
};


MDBValue.syntaxViews = syntaxViews;


// Create an E instance with an inline element describing a Lua value.
//
// `desc` is an MDB Lua "Value Description" (see mdb.txt)
//
MDBValue.createValueView = function (desc) {
    var type = this.descToType(desc);
    if (type == 'table') {
        return this.createTableView(desc);
    }
    var view = syntaxViews[type] || syntaxViews.keyword;
    return view.create(desc);
};


module.exports = MDBValue;
