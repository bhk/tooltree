// mdbview_q.js

'use strict';

require('dom_emu.js');
require('settimeout_emu.js');
var mdb = require('mdb_emu.js');

var MDBView = require('mdbview.js');

var mdbView = MDBView.create(mdb);

window.setTimeout.flush();
