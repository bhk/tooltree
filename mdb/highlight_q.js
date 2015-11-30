'use strict';

var expect = require('expect.js');
var Highlight = require('highlight.js');

var eq = expect.eq;


function nodeCtor(type, str) {
    return type + "(" + str + ")";
}

var hl = Highlight.create(nodeCtor);

function hlt(line, xform) {
    eq(hl.doLine(line).join(' '), xform);
}

// keyword, number, single-line comment
hlt( "local x = 1-- comment",
     "keyword(local) text( x = ) number(1) comment(-- comment)" );

// more complex numbers
hlt( "1. 2.3e+7",
     "number(1.) text( ) number(2.3e+7)");
hlt("1.e5 .1e-2",
    "number(1.e5) text( ) number(.1e-2)" );
hlt( "0xf7F",
     "number(0xf7F)");


// strings
hlt( "'a\\'b'; \"x\\\"y\"",
     "string('a\\'b') text(; ) string(\"x\\\"y\")" );

// long strings
hlt( "[[ [ ] \" ']]; [==[[ ] ]=] ]==]",
     "string([[ [ ] \" ']]) text(; ) string([==[[ ] ]=] ]==])");

// multi-line long strings
hlt( "x [=[abc",
     "text(x ) string([=[abc)");

hlt( "de]]]=]y",
     "string(de]]]=]) text(y)");

hlt( "X [=[ABC",
     "text(X ) string([=[ABC)");

hl.reset();

hlt( "DE]]]=]Y", "text(DE]]]=]Y)");

// long comments
hlt( "--[[abc]]  --[=[def",
     "comment(--[[abc]]) text(  ) comment(--[=[def)");


if (process.env.DOBENCH) {
    var C = require('clocker.js');
    var lines = require('samplelua.js').lines;
    var nlines = lines.length;
    var REPS = 100000;

    var f = function doLine() {
        var hl = Highlight.create(function () { return null;});
        for (var num = 0; num < REPS; ++num) {
            hl.doLine(lines[num % nlines]);
        }
    };

    C.show(f, REPS);
}
