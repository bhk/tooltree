require('dom_emu.js');
var View = require('view.js');
var O = require('observable.js');
var Splitter = require('splitter.js');
var expect = require('expect.js');


var eq = expect.eq;
var assert = expect.assert;


function create(wherea, whereb, wheresize) {
    var size = O.slot('50%');
    var a = View.create({background: '#8a8'});
    var b = View.create({background: '#a88'});

    var props = {};
    props[wherea] = a;
    props[whereb] = b;
    props[wheresize] = size;

    var s = Splitter.create({ $left: a, $right: b, $leftSize: size});
    assert(/_split/.test(a.e.className));
    assert(/_split/.test(b.e.className));
}

create('$left', '$right', '$leftSize');
create('$left', '$right', '$rightSize');
create('$top', '$bottom', '$topSize');
create('$top', '$bottom', '$bottomSize');
