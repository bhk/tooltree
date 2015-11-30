// demo: utility class for look & feel tests
//
//  demo.init : initialize document with content area, note area, and log
//  demo.note : append a note (e.g. instructions for testing)
//  demo.log : add item(s) to the top of the log
//  demo.append : add item(s) to the content area
//  demo.addButton : add a button to the document

'use strict';

var View = require('view.js');
var serialize = require('serialize.js');

var note, content, log, buttons;

var Note = View.subclass({ $tag: 'li', $class: 'demo-note' });
var LogItem = View.subclass({ $class: 'demo-logitem' });
var Content = View.subclass({
    $class: 'demo-content',
    border: '1px solid #888',
    background: 'white',
    position: 'relative'
});


document.body.style.backgroundColor = '#eee';


var demo = {};

demo.init = function (props) {
    content = Content.create(props);

    buttons = View.create({ margin: 6 });

    note = View.create({ margin: '10px 20px', font: '14px Arial, Helvetica'});

    log = View.create({
        margin: 8,
        paddingTop: 8,
        font: '14px Arial, Helvetica',
        border: '0px solid #888',
        borderTopWidth: 1
    });

    var top = View.create(buttons, content, note, log);
    document.body.appendChild(top.e);

    demo.content = content;
};


demo.note = function () {
    for (var ndx = 0; ndx < arguments.length; ++ndx) {
        note.append(Note.create(arguments[ndx]));
    }
};


demo.log = function () {
    var item = LogItem.create.apply(LogItem, arguments);
    log.e.insertBefore(item.e, log.e.firstChild);
};


demo.append = function () {
    content.append.apply(content, arguments);
};


demo.addButton = function (content, onclick) {
    var btn = View.create({$tag: 'button'}, content);
    buttons.append(btn);
    btn.e.onclick = onclick;
};


// create a DOM node that displays `value` serialized
demo.value = function (ovalue) {
    var node = document.createTextNode('');
    View.activate(function (value) {
        node.textContent = serialize(value);
    }, ovalue);
    return View.create({
                 $tag: 'span',
                 fontFamily: 'Menlo, monospace',
                 fontWeight: 'bold'
             }, node);
};


// For interactive sessions...
window.demo = demo;
window.require = require;


module.exports = demo;
