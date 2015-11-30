'use strict';

var View = require('view.js');
var MDBValue = require('mdbvalue.js');


var LocalsItem = View.subclass({
    $class: 'locals-item',
    font: '12px "Menlo", "Monaco", monospace',
    padding: '2px 4px',
    margin: '2px 1px 1px 2px',
    clear: 'left',
    borderBottom: '1px solid #e8e8e8',
    userSelect: 'auto'
});


var LocalsName = View.subclass({
    $class: 'locals-name',
    cssFloat: 'left',
    '?::after': {
        content: '"="',
        marginLeft: 3,
        marginRight: 4
    }
});

var ErrorView = View.subclass({
    $class: 'error',
    font: 'italic 15px "Lucida Grande", Arial',
    color: '#bd0000',
    padding: 10
});


var LocalsView = View.subclass({
    $class: 'locals',
});


LocalsView.initialize = function (mdb, content) {
    View.initialize.call(this);
    this.mdbvalue = MDBValue.create(mdb);
    this.activate(function (data) {
        this.setContent(data instanceof Array ? data.map(this.newItem, this) :
                        typeof data == 'string' ? ErrorView.create(data) :
                        null);
    }.bind(this), content);
};


LocalsView.newItem = function (item) {
    return LocalsItem.create(
        LocalsName.create( String(item.name) ),
        this.mdbvalue.createValueView(item.value)
    );
};


module.exports = LocalsView;
