var serialize = require('serialize.js');

function eq(a,b) {
    if (a != b) {
        console.log(" a = " + String(a));
        console.log(" b = " + String(b));
        throw new Error("assertion failed");
    }
}

eq('1', serialize(1));
eq("'hello'", serialize("hello"));
eq("{a:1,b:2,c:3}", serialize({a:1,b:2,c:3}));
eq("{'a.b':4}", serialize({'a.b':4}));

eq('[1,2,3,4,5,6,7,8,9,10,11]', serialize([1,2,3,4,5,6,7,8,9,10,11]));

var a = [];
a[2] = 'a';
a[1] = 'b';
a[0] = 'c';
eq("[\'c\',\'b\',\'a\']", serialize(a));


var o = {};
o.a = o;
eq(serialize(o), '{a:@0}');


eq('[Function[0],Function[1],Function[0]]', serialize([eq,serialize,eq]));


