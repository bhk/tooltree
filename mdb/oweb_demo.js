// Demonstrate oweb.js working with owebserve.lua

'use strict';

var demo = require('demo.js');
var View = require('view.js');
var OWeb = require('oweb.js');
var xhttp = require('xhttp.js');
var scheduler = require('scheduler.js');


var oweb = OWeb.create(xhttp, scheduler, "/observe");

var Status = View.subclass({
    display: 'inline-block',
    width: 80,
    height: 20,
    border: '2px solid gray',
    margin: '0 3px',
    textAlign: 'center',
    background: '#dae0c0',
    borderRadius: 5
});


var entities = [ 'a', 'b', 'c' ];
var obs;

function createObservables() {
    obs = entities.map(function (name) {
        return oweb.observe(name);
    });
}

createObservables();

var elems = entities.map(function (name) {
                             return Status.create('(' + name + ')');
                         });

demo.init({ height: 26, padding: 10 });


demo.note(
    'NOTE: this must be served from owebtest.lua. Use `make run_owebtest`.',
    'Observed values update only when subscribed',
    'c = c + b',
    'A change to a (or b) affects also c.  These two changes should ' +
        'be communicated in one HTTP transaction.',
    'Try: Subscribe + ++a/++b + Recreate + Subscribe [no data => ' +
        ' the "un-acked unsub" bug]'
);


demo.append(elems);


var act = demo.content;
var regs = null;

function unsubscribe () {
    if (regs) {
        for (var ndx in regs) {
            regs[ndx]();
        }
    }
    regs = null;
}

function subscribe() {
    if (regs) {
        return;
    }
    regs = elems.map(function (elem, index) {
        return act.activate(
            function (value, elem) {
                elem.e.innerHTML = (value == undefined ? ' ' : value);
            },
            obs[index],
            elem
        );
    });
}


demo.addButton('Subscribe', subscribe);

demo.addButton('Unsubscribe', unsubscribe);

demo.addButton('Re-Create', function () {
    unsubscribe();
    createObservables();
});


['a', 'b'].forEach(function (name, index) {
    demo.addButton('++' + name, function () {
        var newValue = (obs[index].getValue() || 0) + 1;
        demo.log(name + " = " + newValue);
        xhttp({
            uri: '/set/' + name,
            body: JSON.stringify(newValue),
            method: 'PUT'
        });
    });
});
