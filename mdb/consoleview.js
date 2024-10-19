'use strict';

var View = require('view.js');
var Class = require('class.js');
var scheduler = require('scheduler.js');
var Anim = require('anim.js').newClass(scheduler);
var handleKeys = require('eventutils.js').handleKeys;
var MDBValue = require('mdbvalue.js');


// Put carent at index `pos` in node `node`.  If `node` is a text node,
// `pos` is a character index; if `node` is an element, `pos` is a child
// node index.
function setCaret(node, pos) {
    var r = document.createRange();
    r.setStart(node, pos);
    r.setEnd(node, pos);

    var s = window.getSelection();
    s.removeAllRanges();
    s.addRange(r);
}


//----------------------------------------------------------------
// History
//----------------------------------------------------------------

var History = Class.subclass();


History.initialize = function () {
    this.a = [];
    this.pos = 0;
    this.size = 0;
};


History.add = function (str) {
    this.a[this.size++] = str;
    this.pos = this.size;
};


History.getPrev = function (strCurrent) {
    if (this.pos > 0) {
        if (this.pos == this.size) {
            this.a[this.size] = strCurrent;
        }
        return this.a[--this.pos];
    }
    return null;
};

History.getNext = function () {
    if (this.pos < this.size) {
        return this.a[++this.pos];
    }
    return null;
};


//----------------------------------------------------------------
// ConsoleView
//----------------------------------------------------------------

var ConsoleItem = View.subclass({
    $class: 'console-item',
    whiteSpace: 'pre-wrap',
    border: '0px solid #e8e8e8',
    padding: '2px 4px 2px 21px',
    position: 'relative',
    userSelect: 'initial',

    '?::before': {
        display: 'block',
        position: 'absolute',
        width: 15,
        left: 0,
        textAlign: 'right',
        top: 1
    },

    '?.command::before': {
        content: '"\\276f"'
    },

    '?.result::before': {
        content: '"="',
        color: '#bbb'
    },

    '?.error::before': {
        content: '"\\2716"',
        fontSize: 15
    },

    '?.command': {
        borderTopWidth: 1,
        color: '#4575da'
    },

    '?.value': {
        borderTopWidth: 0
    },

    '?.error': {
        color: '#d13838'
    },

    // '?.log': { },

    '?.status': {
        background: '#E8ebE8',
        color: '#0a6011',
        fontStyle: 'italic'
    }
});


var ConsolePrompt = ConsoleItem.subclass({
    $class: 'console-prompt',
    color: '#4575da',
    marginBottom: 3,
    fontWeight: 'bold',
    outline: 'none',  // prevent selection outline
    userModify: 'read-write',
    webkitUserModify: 'read-write-plaintext-only',
    borderTopWidth: 1,

    '?::before': {
        content: '"\\276f"'
    }
});


var ConsoleView = View.subclass({
    $class: 'console',
    font: '12px "Menlo", "Monaco", monospace',
    overflow: 'scroll',

    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0
});


// mdb must contain:
//    mdb.console = [observable] console state
//    mdb.sendCommand = function to submit another command
//
ConsoleView.initialize = function (mdb) {
    View.initialize.call(this);

    this.mdb = mdb;
    this.mdbvalue = MDBValue.create(mdb);
    this.history = History.create();

    this.out = View.create();
    this.prompt = ConsolePrompt.create();
    this.append(this.out, this.prompt);

    handleKeys(this.prompt.e, 'keydown', false, {
        Enter: this.enterPressed.bind(this),
        ArrowUp: this.arrowPressed.bind(this),
        ArrowDown: this.arrowPressed.bind(this)
    });

    this.e.onmousedown = function (e) {
        if (e.target == this.e) {
            e.preventDefault();
            this.prompt.e.focus();
        }
    }.bind(this);

    this.activate(this.update.bind(this), mdb.console);
};


ConsoleView.typeToClass = {
    C: 'command',    // commands types by user
    E: 'error',      // error messages
    R: 'result',     // lua value (result from command)
    S: 'status',     // status (e.g. "Starting process...")
    T: 'log',        // text from debug.printf
    V: 'value'       // lua value (logged via debug.log)
};


ConsoleView.update = function (log) {
    if (log == undefined) {
        return;
    }
    var old = this.oldLog || {};
    var unch = (old.a === log.a ? old.len : 0);

    // ASSUME that we encounter EITHER:
    //   * append all of value
    //   * reset entire contents
    if (unch === 0) {
        this.out.setContent();
    }

    for (var n = unch; n < log.len; ++n) {
        this.addItem(log.a[n]);
    }
    this.oldLog = log;
};


function markValues(str, valueCtor) {
    var a = str.split(/![12]/);
    for (var ndx = 0; ndx < a.length; ++ndx) {
        var v = a[ndx].replace("!0", "!");
        if (ndx % 2) {
            v = valueCtor(v);
        }
        a[ndx] = v;
    }
    return a;
}

ConsoleView.addItem = function (item) {
    item = String(item);
    var type = item[0];
    var content = item.substr(1);
    var mv = this.mdbvalue;

    var cls = this.typeToClass[type] || 'log';
    if (type == 'V' || type == 'R') {
        content = mv.createValueView(content);
    } else if (type == 'P') {
        content = markValues(content, mv.createValueView.bind(mv));
    }

    var emsg = ConsoleItem.create(content).enableClass(cls);
    this.out.append(emsg);
    this.exposeBottom();
};


ConsoleView.enterPressed = function () {
    var text = this.prompt.e.textContent;
    if (text != '') {
        this.history.add(text);
        this.prompt.setContent();
        this.mdb.sendCommand(text);
    }
};


ConsoleView.arrowPressed = function (evt) {
    var e = this.prompt.e;
    var text = (evt.key == 'ArrowUp' ?
                this.history.getPrev(e.textContent) :
                this.history.getNext(e.textContent) );
    if (text != null) {
        e.textContent = text;
        setCaret(e, e.childNodes.length);
    }
};


ConsoleView.focus = function () {
    this.prompt.e.focus(true);
};


ConsoleView.showMessage = function (type, message) {
    var emsg = E(type, message);
    this.out.append(emsg);
    this.exposeBottom();
};


ConsoleView.exposeBottom = function () {
    var e = this.e;

    window.setTimeout(function () {
        var top0 = e.scrollTop;
        // this assumes border and margin are zero (?)
        var top1 = e.scrollHeight - e.offsetHeight;
        if (top1 > top0) {
            Anim.create(e, 'expose')
                .move(top0, top1, function (top) { e.scrollTop = top; })
                .start();
        }
    }, 0);
};


module.exports = ConsoleView;
ConsoleView.markValues = markValues; // for testing
