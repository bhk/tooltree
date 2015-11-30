// initialize browser globals & minimal DOM API support

'use strict';

require('dom_emu.js');
require('settimeout_emu.js');
var O = require('observable.js');
var expect = require('expect.js');
var eq = expect.eq;

var View = require('view.js');
var sheet = document.styleSheets[0];
expect.assert(sheet);


var rule;
function lastOf(a) {
    return a[a.length-1];
}


// View.normalizeX

eq('cssFloat', View.normalizeName('float'));
eq('webkitBoxFlex', View.normalizeName('boxFlex'));

eq('2px', View.normalizeValue(2));
eq('float -webkit-transform -moz-bar -ms-baz',
   View.normalizeValue('#{float} #{transform} #{MozBar} #{msBaz}'));


// View.scanProps

var obj = {};
var props = {
    height: 1,
    transform: '#{transform} 1s',
    $abc: 1,
    '?.on': {
        top: 2,
        $def: 2
    }
};
var rules = [];
View.scanProps(props, obj, rules, '');
eq(obj.$abc, 1);
eq(obj.$def, undefined);
eq(rules.length, 2);

eq(rules[0],
   {
       selector: '',
       names: ['height', 'webkitTransform'],
       values: ['1px', '-webkit-transform 1s']
   });

eq(rules[1],
   {
       selector: '{?.on}',
       names: ['top'],
       values: ['2px']
   });


// create and use a subclass

var Foo = View.subclass({
    $class: 'foo',
    $tag: 'span',

    color: 'black',

    '?:hover': {
        color: 'blue'
    },

    '?.enabled': {
        color: 'red'
    }
});

var c1 = document.createTextNode('text');
var c2 = document.createElement('div');

var e = Foo.create(c1, ['str', c2]).e;
eq(3, e.childNodes.length);
eq(e.tagName, 'span');
eq(e.className, '_foo');

eq(sheet.cssRules[0].selectorText, '._foo');
eq(sheet.cssRules[1].selectorText, '._foo.enabled');
eq(sheet.cssRules[1].style.color, 'red');
eq(sheet.cssRules[2].style.color, 'blue');


// prefix selectors
var Foo2 = View.subclass({
    $class: 'foo2',
    '.on > ?': {
        color: '#abc'
    }
});
rule = lastOf(sheet.cssRules);
eq(rule.selectorText, '.on > ._foo2');
eq(rule.style.color, '#abc');


// enableClass(cls, true/false)

var foo = Foo.create();
eq(foo.e.className, '_foo');
foo.enableClass('x', true);
eq(foo.e.className, '_foo x');

foo.enableClass('x', false);
eq(foo.e.className, '_foo');

foo.e.className = '';
foo.enableClass('x', true).enableClass('y', true);
eq(foo.e.className, 'x y');

// enableClass(cls)  ==>  enableClass(cls, true)
foo.e.className = '';
foo.enableClass('x');
eq(foo.e.className, 'x');

// enableClasses()

foo.e.className = 'y';
foo.enableClasses('x y x');
eq(foo.e.className, 'y x');



// inheritance / subclassing

var Bar = Foo.subclass({
    $class: 'bar',
    color: 'white'
});

var bar = Bar.create().e;

eq(bar.className, '_foo _bar');
eq(bar.tagName, 'span');
rule = lastOf(sheet.cssRules);
eq(rule.selectorText, '._foo._bar');


// transform --> webkitTransform

void View.subclass({ transform: 'xyz' });
rule = lastOf(sheet.cssRules);
eq(rule.style.webkitTransform, 'xyz');


// Property assignment arguments to createElement()
// element-specific selectors

var view = View.create(
    { top: 5 },
    {
        $id: 'x',
        color: 'blue',
        '?:hover': { color: 'red' }
    }).e;

eq(view.id, 'x');
eq(view.style.color, 'blue');

rule = lastOf(sheet.cssRules);
eq(rule.selectorText, '#x:hover');
eq(rule.style.color, 'red');


// activate/deactivate/destroy

view = View.create();
var sum = 0;
var ov1 = O.slot(1);
var dereg = view.activate(function (n) {
                              sum += n;
                          }, ov1);

// ASSERTION: activate subscribes to observables.
eq(ov1.subs.length, 1);

// ASSERTION: activate triggers asynchronous update.
eq(sum, 1);
ov1.setValue(2);
eq(sum, 1);
window.setTimeout.flush();
eq(sum, 3);

// ASSERTION: dereg unsubscribes.
eq(ov1.subs.length, 1);
dereg();
eq(ov1.subs.length, 0);

// ASSERTION: destroy unsubscribes to all.
view.activate(function (n) { sum += n; }, ov1);
view.activate(function () {}, ov1);
eq(ov1.subs.length, 2);
view.destroy();
eq(ov1.subs.length, 0);


if (process.env.DOBENCH) {
    var Clocker = require('clocker.js');
    var v = View.create({});
    v.e.className = 'foo bar';
    Clocker.show(
        function enableClass() {
            v.enableClass('bar', false);
            v.enableClass('bar', false);
            v.enableClass('bar', true);
            v.enableClass('bar', true);
        },
        4);
}
