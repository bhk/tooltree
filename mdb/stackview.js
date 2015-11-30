'use strict';

var View = require('view.js');
var O = require('observable.js');
var captureClick = require('eventutils.js').captureClick;


function findInChild(elem, parent) {
    while (elem && elem.parentNode != parent) {
        elem = elem.parentNode;
    }
    return elem;
}

function childIndex(child) {
    var prev;
    for (var n = 0; (prev = child.previousElementSibling); ++n) {
        child = prev;
    }
    return n;
}

function notdir(str) {
    return str.match(/([^/]*)$/g)[0];
}


//----------------------------------------------------------------
// StackFrame
//----------------------------------------------------------------

var FramePos = View.subclass({
    $class: 'frame-pos',
    cssFloat: 'right',
    fontSize: '80%',
    margin: '1px 0 0 0'
});


var FrameName = View.subclass();


var StackFrame = View.subclass({
    $class: 'stack-frame',
    font: '12px "Menlo", "Monaco", monospace',
    padding: '2px 4px',
    margin: '1px 1px 1px 2px',
    border: '1px solid transparent',
    borderRadius: '5px',
    userSelect: 'none',

    '?:hover': {
        borderColor: '#bbb'
    },

    '?:active': {
        textShadow: '1px 1px 1px white'
    },

    '?:hover:active': {
        boxShadow: '-1px -1px 2px rgba(0,0,0,0.1), 1px 1px 2px #fff',
        backgroundColor: '#e0e0e0',
        borderColor: '#777 #AAA #AAA #777'
    },

    '?.selected': {
        background: '#637FD3',
        color: '#FAF7F5'
    },

    '?.selected:hover': {
        borderColor: 'transparent'
    },

    '?.selected:active': {
        textShadow: 'none'
    },

    '?.selected:hover:active': {
        boxShadow: 'none',
        backgroundColor: '#5370ca',
        color: '#f0eae5'
    }
});


StackFrame.initialize = function (frame) {
    View.initialize.call(this);

    this.frame = frame;

    var file = frame.file && notdir(frame.file) || frame.desc || '?';
    var pos = file + ':' + (frame.line || '?');
    var func = frame.name || '\u2014';

    if (frame.what === 'main') {
        func = View.create({$tag: 'i'}, '(main)');
    } else if (frame.what === 'C') {
        pos = '[C]';
    } else if (frame.what === 'D') {
        func = View.create({$tag: 'i'}, frame.name);
        pos = "debugger";
    }

    this.append( FramePos.create(pos),
                 FrameName.create(func) );
};


//----------------------------------------------------------------


var StackView = View.subclass({
    $class: 'stack',
    overflowY: 'auto',
    overflowX: 'hidden'
});


StackView.initialize = function (content) {
    View.initialize.call(this);

    // null => nothing selected
    this.selection = O.slot(null);

    this.activate(function (data) {
        var c;
        if (data instanceof Array) {
            c = data.map(StackFrame.create, StackFrame);
            this.items = c;
            this.xcap = captureClick(this.e, this.doClick, this);
        } else {
            if (this.xcap) {
                this.xcap();
            }
            this.items = [];
            c = (data && this.newMessage(data));
        }
        this.selectItem(0);
        this.setContent(c);
    }.bind(this), content);
};


StackView.newMessage = function (str) {
    return View.create({
        $class: 'info',
        font: '16px "Helvetica", sans-serif',
        fontStyle: 'italic',
        margin: '10px',
        color: '#aa0000'
    }, str);
};


StackView.doClick = function (elem, evtUp, evtDown) {
    var eclk = findInChild(evtUp.target, this.e);
    if (eclk != findInChild(evtDown.target, this.e)) {
        return;
    }

    this.selectItem(childIndex(eclk));
};


StackView.selectItem = function (index) {
    if (this.selectedView) {
        this.selectedView.enableClass('selected', false);
        this.selectedView = null;
    }

    var view = this.items[index];
    if (view) {
        view.enableClass('selected');
        this.selectedView = view;
    }

    this.selection.setValue(view && {index: index, frame: view.frame});
};


module.exports = StackView;
