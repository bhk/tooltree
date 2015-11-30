'use strict';

var View = require('view.js');
var O = require('observable.js');
var Button = require('button.js');
var Splitter = require('splitter.js');
var CodeView = require('codeview.js');
var StackView = require('stackview.js');
var LocalsView = require('localsview.js');
var ConsoleView = require('consoleview.js');
var handleKeys = require('eventutils.js').handleKeys;
var scheduler = require('scheduler.js');
var Anim = require('anim.js').newClass(scheduler);


//----------------------------------------------------------------
// Chrome & Fill base classes
//----------------------------------------------------------------


// background typically used by instrumentation in the app
//
var Chrome = View.subclass({
    $class: 'chrome',
    font: '12px "Lucida Grande", "Helvetica", sans-serif',
    fontWeight: 'bold',
    userSelect: 'none',
    background: 'url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAX0lEQVQYV42POw7AMAhDQerA/U/WoYOPwlApJeE7FilSiI154RtYQkpEYsdrdgwzvPZ4baUubWE8WK725JHDfBJSyoBfK9SYdnAkdHxhBNJgUKOX2p3A7N/0mtPOofQBFAg1MebnsAUAAAAASUVORK5CYII=), #d8d8d8'
});


var Fill = View.subclass({
    $class: 'fill',
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    boxSizing: 'border-box'
});


//----------------------------------------------------------------
// Section
//----------------------------------------------------------------


var sectionTitleHeight = 20;

var SectionTitle = Chrome.subclass({
    $class: 'section-title',
    boxSizing: 'border-box',
    height: sectionTitleHeight,
    borderStyle: 'solid',
    borderWidth: 1,
    borderColor: '#f2f2f2 #999 #999 #f2f2f2',
    padding: '2px 5px',
    color: '#333',

    position: 'absolute',
    left: 0,
    right: 0,
    boxShadow: '0 3px 3px -1px white', /* #f0f0f0 */

    '.empty > ?': {
        boxShadow: 'none'
    }
});


var SectionBody = Fill.subclass({
    $class: 'section-body',
    marginTop: sectionTitleHeight,
    overflowY: 'auto',
    overflowX: 'hidden'
});


var SectionMask = Fill.subclass({
    $class: 'section-mask',
    top: '100%',
    height: 0,   // not disabled
    backgroundColor: '#ddd',
    opacity: '0',

    '.disabled > ?': {
        top: sectionTitleHeight,
        height: 'auto',
        bottom: 0,
        opacity: '0.70',
        transition: 'opacity 0.5s cubic-bezier(0.5, 0, 0.8, 0.5)'
    }
});


var SectionView = View.subclass({
    $class: 'section',
    borderWidth: 0,
    background: 'white', // #eaeaea

    // Interferes with splitter transition animation:
    //    transition: 'background-color 0.15s'

    overflow: 'hidden'
});



SectionView.initialize = function (_title, _body, _disable) {
    var titleView = SectionTitle.create();
    var bodyView = SectionBody.create();
    View.initialize.call(this, titleView, bodyView, SectionMask.create() );

    this.activate(function (title) {
        titleView.setContent(title);
    }, _title);

    this.activate(function (body) {
        bodyView.setContent(body);
        this.enableClass('empty', !body);
    }.bind(this), _body);

    this.activate(this.disable.bind(this), _disable);
};


// grey out and prevent clicking on controls
//
SectionView.disable = function (isDisabled) {
    this.enableClass('disabled', !!isDisabled);
};



//----------------------------------------------------------------
// Toolbar
//----------------------------------------------------------------

var ButtonArt = View.subclass({
    $class: 'art',
    border: '0px solid #a0a0a0',

    '.enabled > ?': {
        borderColor: '#333',
        boxShadow: '2px 2px 4px rgba(0,0,0,.4)'
    },

    '.enabled:hover > ?': {
        boxShadow: 'none'
    },

    '.enabled:active > ?': {
        boxShadow: '1px 1px 1px #fff'
    }
});


// Console Button label

var ConsoleLine = ButtonArt.subclass({
    borderColor: 'inherit',
    borderBottomWidth: 1,
    width: 7,
    height: 2,
    boxShadow: 'none'
});


var ConsoleLabel = ButtonArt.subclass({
    // this element is a bordered rectangle
    width: 8,
    height: 12,
    borderWidth: 2,
    margin: '4px 4px',
    padding: '0 1px'
});


function createConsoleLabel() {
    return ConsoleLabel.create( ConsoleLine.create(),
                                ConsoleLine.create({width: 3}),
                                ConsoleLine.create({width: 5}) );
}


function createGoLabel() {
    return [ {paddingLeft: 3, paddingTop: 1}, "\u25b6" ];
}


var FileNameView = View.subclass({
   font: '12px "Menlo", "Monaco", sans-serif',
   padding: '2px 4px 1px',
   border: '1px solid #AAA',
   borderColor: '#BBB #F0F0F0 #F0F0F0 #BBB',
   borderRadius: 3,
   cssFloat: 'right',
   margin: '3px 10px'
});


//----------------------------------------------------------------
// ToolbarView
//----------------------------------------------------------------

var ToolbarView = Chrome.subclass({
    $class: 'toolbar',
    boxSizing: 'border-box',
    borderTop: '1px solid #f0f0f0',
    borderBottom: '1px solid #999',
    padding: '0 0 0 4px'
});


ToolbarView.buttons = [
    {id: 'restart',  content: "\u21bb",             title: "Restart target process"},
    {id: 'pause',    content: '||',                 title: "Pause execution"},
    {id: 'go',       content: createGoLabel(),      title: "Resume execution"},
    {id: 'stepOver', content: "\u21e3",             title: "Step over function calls"},
    {id: 'stepIn',   content: "\u21e2",             title: "Step into function calls"},
    {id: 'stepOut',  content: "\u21e0",             title: "Step out of function"},
    {id: 'console',  content: createConsoleLabel(), title: "View console output"}
];


ToolbarView.initialize = function (onclick, enabledSet, fileName) {
    View.initialize.call(this);

    // id -> view
    var map = Object.create(null);

    var views = this.buttons.map(function (b) {
        return map[b.id] = Button.create(b.content, {
            fontFamily: 'Helvetica, sans-serif',
            $onclick: onclick,
            $clickArg: b.id,
            $title: b.title
        });
    });

    this.append(views);

    var nameView = FileNameView.create();

    this.activate(function (name) {
        nameView.setContent(name);
    }, fileName);
    this.append(nameView);

    // Enable listed IDs; disable all others
    this.activate(function (names) {
        for (var k in map) {
            map[k].enable( names.indexOf(k) >= 0 );
        }
    }, enabledSet);

    this.simulate = function (id) {
        if (map[id]) {
            map[id].flash();
            onclick(id);
        }
    };
};


//----------------------------------------------------------------
// OverlayView
//----------------------------------------------------------------


var OverlayContent = View.subclass({
   $class: 'overlay-content',
   position: 'absolute',
   marginLeft: 'auto',
   marginRight: 'auto',
   left: 0,
   right: 0,
   width: '70%',
   minWidth: 380,
   top: '20%',
   height: '60%',
   maxHeight: 300,
   overflow: 'hidden',
   border: '4px solid #6384A7',
   borderRadius: 7,
   background: '#FFF',
   font: '14px Helvetica'
});


var OverlayText = Fill.subclass({
   $class: 'overlay-text',
   padding: 20,
   overflow: 'scroll'
});


var OverlayButton = Button.subclass({
   $class: 'overlay-button',
   position: 'absolute',
   top: 2,
   right: 2,
   fontSize: 25,
   lineHeight: 21,
   margin: 0,
   color: '#a53f3f',
   textShadow: '1px 1px 2px rgba(71,32,32,0.22)'
});


var OverlayView = Fill.subclass({
   $class: 'overlay',
   display: 'none',
   backgroundColor: 'rgba(194, 194, 194, 0.6)'
});


OverlayView.initialize = function (text) {
    View.initialize.call(this);

    var button = OverlayButton.create("\u2297", {
        $onclick: this.toggle.bind(this),
        $title: 'Close window'
    });

    this.append(
        OverlayContent.create(
            OverlayText.create(text),
            button
        )
    );

    this.shown = false;

    this.e.onmousedown = function (evt) {
        if (evt.eventPhase == evt.AT_TARGET) {
            this.show(false);
            evt.preventDefault();
            evt.stopPropagation();
        }
    }.bind(this);
};


OverlayView.show = function (bOn) {
    bOn = !!bOn;
    if (bOn == this.shown) {
        return;
    }
    this.shown = bOn;

    var a = Anim.create(this.e, 'show-hide');

    if (bOn) {
        this.unHandle = handleKeys(document.body, 'keydown', false, {
            'U+001B': this.show.bind(this, false)
        });
        a.css({ display: 'block', opacity: '0' })
            .cssTransition({opacity: '1'}, 500);
    } else {
        this.unHandle();
        a.cssTransition({opacity: '0'}, 250)
            .css({display: 'none'});
    }
    a.start();
};


OverlayView.toggle = function () {
    this.show(!this.shown);
};


//----------------------------------------------------------------
// MDBView
//----------------------------------------------------------------


//---------------- stack ----------------

function modeToStackTitle(mode) {
    switch (mode) {
    case 'pause': return 'Paused at:';
    case 'run':   return 'Running...';
    case 'exit':  return 'Exited';
    case 'down':  return 'Connecting...';
    case 'busy':  return 'Target not responding...';
    default:       return 'Error...';
    }
}


var StackPane = SectionView.subclass();


StackPane.initialize = function (mdb) {
    var stackTitle = O.func(modeToStackTitle, mdb.mode);

    var stack = StackView.create(
        O.func(function (mode, stack) {
            switch (mode) {
            case 'exit':   return 'Target process has exited';
            case 'error':  return 'Internal error';
            default:       return (stack ? stack : 'Loading...');
            }
        }, mdb.mode, mdb.stack)
    );

    var disabled = O.func(function (mode) {
        return mode != 'pause';
    }, mdb.mode);

    SectionView.initialize.call(this, stackTitle, stack, disabled);

    this.selection = stack.selection;
};


//---------------- locals ----------------
//
// Display the local variables for the currently-selected stack frame


var LocalsPane = SectionView.subclass();


LocalsPane.initialize = function (mdb, stack) {
    var data = null;
    var locals = O.func(function (sel, fetchLocals) {
        if (!sel) {
            // nothing to show (exited, not connected)
            return undefined;
        }

        return fetchLocals(sel.index + 1);
    }, stack.selection, mdb.fetchLocals);

    var localsView = LocalsView.create(mdb, locals);

    var localsDisabled = O.func(function (mode, data) {
        return mode != 'pause' || !data;
    }, mdb.mode, locals);
    SectionView.initialize.call(this, 'Local Variables', localsView, localsDisabled);
};


//---------------- code ----------------
//
// Display the source code corresponding to the most-recently selected stack
// frame.  Update filename and breakpoints when source text is updated. Flag
// the current line of execution.


function clone(a) {
    var o = Object.create(Object.getPrototypeOf(a));
    for (var k in a) {
        o[k] = a[k];
    }
    return o;
}


// return an observable that gets/sets the breakpoints for a particular file
//
function extractFileBPs(mdb, file) {
    var recent;

    var o = O.func(function (bps) {
        recent = bps;
        return bps && bps[file];
    }, mdb.breakpoints);

    o.setValue = function (fileBPs) {
        var value = clone(recent);
        value[file] = fileBPs;
        mdb.breakpoints.setValue(value);
    };

    return o;
}


var CodePane = CodeView.subclass();

CodePane.initialize = function (mdb, stack) {
    CodeView.initialize.call(this, {borderLeft: '1px solid #666'});
    var currentFile;

    // Update CodeView and return name of currently-displayed file.
    //
    this.fileName = O.func(function (sel, fetchSource, mode) {
        var frame = sel && sel.frame;
        var file = frame && frame.file;
        var source;

        if (file) {
            source = fetchSource(file);
            if (typeof source == "string") {
                if (currentFile != file) {
                    currentFile = file;
                    this.setText(source, extractFileBPs(mdb, file));
                }
                this.flagLine(mode == 'pause' ? frame.line : null);
            }
        }
        return currentFile;
    }.bind(this), stack.selection, mdb.fetchSource, mdb.mode);

    this.activate(this.filename);  // keep codeview updated
};


//---------------- console ----------------

var ConsolePane = SectionView.subclass();


ConsolePane.initialize = function (mdb) {
    SectionView.initialize.call(this, 'Console', ConsoleView.create(mdb));

    this.size = O.slot('0%');

    this.sizeWhenOpen = '38%';

    this.toggle = function () {
        var v = this.size.getValue();
        if (v == '0%') {
            v = this.sizeWhenOpen;
        } else {
            this.sizeWhenOpen = v;
            v = '0%';
        }
        this.size.setValue(v);
    };
};


//---------------- toolbar ----------------


function modeToButtons (mode) {
    switch (mode) {
    case 'pause': return ['restart', 'go', 'stepOver', 'stepIn',
                          'stepOut', 'console'];
    case 'run':   return ['pause', 'restart', 'console'];
    case 'busy':  return ['restart', 'console'];
    case 'exit':  return ['restart', 'console'];
    default:      return ['console'];
    }
}


var ToolbarPane = ToolbarView.subclass();


ToolbarPane.initialize = function (mdb, code, console) {
    var onbutton = function (name) {
        if (name == 'console') {
            console.toggle();
        } else {
            mdb.action(name);
        }
    };
    var enabled = O.func(modeToButtons, mdb.mode);

    ToolbarView.initialize.call(this, onbutton, enabled, code.fileName);
};


//---------------- overlay ----------------


var Key = View.subclass({
   cssFloat: 'right',
   minWidth: 16,
   minHeight: 19,
   font: '9px Monaco, Courier, monospace',
   lineHeight: 19,
   padding: '0 1px 0 2px',
   color: '#FFF',
   background: '#595E74',
   border: '2px solid #212124',
   borderRadius: 3,
   borderTopColor: '#8287AF',
   borderLeftColor: '#8287AF',
   margin: '0 2px',
   textAlign: 'center'
});


var TTKey = Key.subclass({
    $tag: 'tt',
    fontWeight: 'bold',
    font: 'bold 14px Courier',
    lineHeight: 19
});


function createOverlay() {
    var H1 = View.subclass({fontWeight: 'bold', fontSize: '125%'});
    var HR = View.subclass({$tag: 'hr'});
    var Table = View.subclass({$tag: 'table'});
    var TR = View.subclass({$tag: 'tr'});
    var TH = View.subclass({$tag: 'th', textAlign: 'right', padding: 5});
    var TD = View.subclass({$tag: 'td', padding: 5});

    function row(key, desc) {
        return TR.create( TH.create(key), TD.create(desc) );
    }

    function CA(key) {
        return [ TTKey.create(key), Key.create('alt'), Key.create('ctl') ];
    }

    var text = [
        H1.create( 'Keyboard Shortcuts' ),
        HR.create(),
        Table.create(
            row( CA('\u2193'), 'Step over function calls'),
            row( CA('\u2192'), 'Step into function calls'),
            row( CA('\u2190'), 'Step out of current function'),
            row( CA('enter'), 'Continue execution'),
            row( CA('space'), 'Open/close console'),
            row( TTKey.create('?'), 'Show/dismiss this dialog')
        )
    ];

    return OverlayView.create(text);
}


//---------------- shortcuts ----------------

function installShortcuts(toolbar, overlay) {

    // trapping `keydown` prevents default behavior (otherwise,
    // the focused element might scroll).
    handleKeys(document.body, 'keydown', true, {
        A_C_Down: function () { toolbar.simulate('stepOver'); },
        A_C_Right: function () { toolbar.simulate('stepIn'); },
        A_C_Left: function () { toolbar.simulate('stepOut'); },
        A_C_Enter: function () { toolbar.simulate('go'); },
        'A_C_U+0020': function () { toolbar.simulate('console'); }
    });

    handleKeys(document.body, 'keypress', false, {
        '?': function () {
            // ignore if any element has focus...
            if (document.activeElement !== document.body) {
                return false;
            }
            overlay.toggle();
            return true;
        }.bind(this)
    });
}


//---------------- MDBView ----------------


var MDBView = Fill.subclass({
    $class: 'mdb'
});


MDBView.initialize = function (mdb) {
    View.initialize.call(this);

    var stack = StackPane.create(mdb);
    var locals = LocalsPane.create(mdb, stack);
    var code = CodePane.create(mdb, stack);
    var console = ConsolePane.create(mdb);
    var toolbar = ToolbarPane.create(mdb, code, console);
    var overlay = createOverlay();

    installShortcuts(toolbar, overlay);

    this.append(
        Splitter.create({
            $bottomSize: console.size,
            $bottom: console,
            $top: Splitter.create({
                $topSize: 32,
                $top: toolbar,
                $bottom: Splitter.create({
                    $leftSize: O.slot('30%'),
                    $right: code,
                    $left: Splitter.create({
                        $topSize: O.slot('50%'),
                        $top: stack,
                        $bottom: locals})})})}),
        overlay);
};


module.exports = MDBView;
