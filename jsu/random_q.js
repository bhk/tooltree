var expect = require('expect.js');

r = require("random.js");

var str = r(200);

expect.eq(str.length, 200);
expect.assert( str.match(/^[+\/A-Za-z0-9]*$/) );
