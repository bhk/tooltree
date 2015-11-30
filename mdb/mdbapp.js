// title: MDB

'use strict';

var mdb = require('mdb.js');
var View = require('view.js');
var MDBView = require('mdbview.js');
var MDBValue = require('mdbvalue.js');
var ConsoleView = require('consoleview.js');


mdb.openValue = function (name) {
    window.open('#explore=' + name, "MDB_" + name);
};


var body = View.wrap(document.body);
body.append({ margin: 0});


function hashCB() {
    var hash = window.location.hash || '#';
    var view;
    var overflow = '';
    var m;

    if (hash == '#console') {
        view = ConsoleView.create(mdb);
    } else if (null != (m = hash.match('^#explore=([A-Za-z]*)(.*)'))) {
        var desc = m[1] + ' ' + m[2];
        var mdbvalue = MDBValue.create(mdb);
        view = mdbvalue.createTableView(desc, true);
        view.append({ margin: 12 });
    } else {
        view = MDBView.create(mdb);
        overflow = 'hidden';
    }
    body.setContent(view, {overflow: overflow});
}

hashCB();
window.onhashchange = hashCB;

// for debugging
window.require = require;
