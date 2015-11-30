// codeview.js

'use strict';

var View = require('view.js');
var Highlight = require('highlight.js');
var captureClick = require('eventutils.js').captureClick;
var scheduler = require('scheduler.js');
var Anim = require('anim.js').newClass(scheduler);
var MDBValue = require('mdbvalue.js');


// number of milliseconds after text is shown before smooth scrolling is used
var CONTEXT_TIME = 100;

// `height` of a TextLine element.  Not to be confused with `line-height`. :-)
var HEIGHT = 16;


function highlightNode(type, str) {
    var c = MDBValue.syntaxViews[type];
    return (c ? c.create(str) : str);
}


//----------------------------------------------------------------
// Gutter & Text
//----------------------------------------------------------------


var pad = Math.round(HEIGHT * 3/16);
var px = Math.round(HEIGHT / 16);
var gutterWidth = HEIGHT * 38/16;


var Gutter = View.subclass({
    $class: 'gutter',
    position: 'absolute',
    boxSizing: 'border-box',
    left: 0,
    width: gutterWidth,
    top: 0,
    // extend to at least the height of the CodeView area
    minHeight: '100%',
    color: '#999',
    background: '#eaeaea',
    borderRight: px + 'px solid #ddd',
    textAlign: 'right',
    paddingTop: pad,
    paddingBottom: pad,
    // when text is scrolled to the left, fade out in the padding area
    ':not(.empty) > ?': {
       boxShadow: pad+'px 0 ' + pad + 'px 0 white'
    }
});


var glRadius = HEIGHT * 6/16;
var glExtend = HEIGHT * 3/16;
var glPad = HEIGHT * 3/16;
var glContent = HEIGHT - glPad*2;

var GutterLine = View.subclass({
   $class: 'gutter-line',
   height: HEIGHT,
   boxSizing: 'border-box',
   padding: glPad,
   fontSize: '80%',
   transition: 'background-color 0.3s, color 0.3s',

   '?:not(.flag):hover': {
      backgroundColor: '#dedede'
   },

   '?.flag': {
       background: '#637FD3',
       color: '#FAF7F5',
       position: 'relative',

       // make rounded and expand on right side
       borderTopRightRadius: glRadius,
       borderBottomRightRadius: glRadius,
       marginRight: -glExtend,
       // increase paddingRight to move text back to where it belongs
       paddingRight: glPad + glExtend
   }
});


var bpDiam = Math.round(HEIGHT * 10/16);

var Breakpoint = View.subclass({
    $class: 'bp',
    boxSizing: 'border-box',
    height: bpDiam,
    width: bpDiam,
    marginTop: (glContent - bpDiam)/2,
    border: px + 'px solid transparent',
    borderRadius: bpDiam / 2 + 1,

    // We want parent-relative positioning, but we don't want to influence
    // positioning of sibling content, so we use `position: absolute` and
    // leave `left` and `top` as `auto`. [See CSS2.1 section 10.3.7]
    position: 'absolute',

    ':hover > ?': {
        borderColor: 'rgba(77, 0, 0, 0.16)',
        transition: 'border-color 0.5s'
    },

    ':hover:active > ?': {
        backgroundColor: 'rgba(124, 1, 1, 0.67)',
        borderColor: 'rgba(77, 0, 0, 1)'
    },

    '.bp > ?': {
        borderColor: '#4D0000',
        backgroundColor: '#e75b5b',
        boxShadow: '1px 1px 2px rgba(46, 0, 0, 0.61)'
    }
});


var Text = View.subclass({
    $class: 'text',
    padding: pad,
    lineHeight: HEIGHT,
    userSelect: 'text',

    position: 'absolute',
    top: 0,
    bottom: 0,
    left: gutterWidth,

    marginLeft: px * 2
});


var TextLine = View.subclass({
   $class: 'text-line',
   height: HEIGHT
});


//----------------------------------------------------------------
// CodeView
//----------------------------------------------------------------

var CodeView = View.subclass({
    $class: 'codeview',
    background: '#fff',
    color: '#000',
    overflow: 'scroll',
    whiteSpace: 'pre',
    fontFamily: 'Menlo, Monaco, monospace',
    fontSize: HEIGHT * 3/4,
    transition: 'background-color 0.15s',
    userSelect: 'none',

    // fill
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,

    '?.empty': {
        backgroundColor: '#eee'
    }
});


CodeView.postInit = function () {
    this.gutter = Gutter.create();
    this.text = Text.create();
    this.append(this.text, this.gutter);
    this.eScroll = this.e;
    this.hl = Highlight.create(highlightNode);
    this.setText();

    // anchor gutter at left of CodeView (but let it scroll up/down)
    var gutterStyle = this.gutter.e.style;
    var thisElem = this.e;
    var oldLeft = undefined;
    this.e.onscroll = function () {
        var left = thisElem.scrollLeft;
        if (left !== oldLeft) {
            gutterStyle.left = left + 'px';
            oldLeft = left;
        }
    }.bind(this);

    captureClick(this.gutter.e, this.gutterClick, this);
};


// `text`: source code as a single string
// `breakpoints`: [observable/settable] an array of line numbers (1 == first
//   line), or null/undefined, which represents an empty set.
//
CodeView.setText = function (text, breakpoints) {
    // breakpoints
    if (this.bpActive) {
        this.bpActive();
        this.bpActive = null;
    }
    this.breakpoints = breakpoints;

    this.enableClass('empty', (text == null));
    this.eScroll.scrollTop = 0;

    // Replace text content

    var lines = (text == null ? [] : text.split('\n'));
    this.hl.reset();

    function makeLine(str) {
        return TextLine.create(this.hl.doLine(str));
    }

    this.text.setContent(lines.map(makeLine, this));

    // Replace gutter content

    function makeGutterLine(_, ndx) {
        return GutterLine.create( Breakpoint.create(), String(ndx+1) );
    }

    this.gutterLines = lines.map(makeGutterLine, this);
    this.gutter.setContent(this.gutterLines);
    this.lineFlagged = null;  // GutterLine | null
    this.linesWithBP = {};    // line -> true  (for all lines marked with bp)

    if (breakpoints != null) {
        this.bpActive = this.activate(this.updateBP.bind(this), breakpoints);
    }

    // Make note that visual context has been reset.
    this.timeShown = scheduler.now();
};


CodeView.updateBP = function (lines) {
    var elems = this.gutterLines;
    var old = this.linesWithBP;
    var show = {};
    this.linesWithBP = show;

    var lnum;
    for (var n in (lines || [])) {
        lnum = lines[n];
        show[lnum] = true;
        old[lnum] = (old[lnum] ? null : 'add');
    }

    // old[lnum] == true  => to be removed
    // old[lnum] == 'add' => to be added
    for (lnum in old) {
        var e = elems[lnum-1];
        if (e && old[lnum]) {
            e.enableClass('bp', old[lnum] === 'add');
        }
    }
};


CodeView.gutterClick = function (elem, evtUp, evtDown) {
    if (!this.gutterLines || !this.breakpoints) {
        return;
    }

    var gutterElem = this.gutter.e;
    function findLine(evt) {
        var e = evt.target;
        while (e && e.parentNode != gutterElem) {
            e = e.parentNode;
        }
        return e;
    }

    var eup, lnum;
    var line = ( (eup = findLine(evtUp)) != null &&
                 eup == findLine(evtDown) &&
                 (lnum = Number(eup.textContent)) &&
                 this.gutterLines[lnum-1] );

    if (!line) {
        return;
    }

    // Update the element synchronously to avoid flicker
    var shown = this.linesWithBP;
    line.enableClass('bp', !shown[lnum]);
    if (shown[lnum]) {
        delete shown[lnum];
    } else {
        shown[lnum] = true;
    }

    var bp = Object.keys(shown)
        .map(Number)
        .sort(function (a,b) { return a > b; });
    this.breakpoints.setValue(bp);
};


// Display "flag" on the specified line and scroll it into view.
//
CodeView.flagLine = function (num) {
    var line = this.gutterLines[num-1];

    if (this.lineFlagged) {
        this.lineFlagged.enableClass('flag', false);
    }
    this.lineFlagged = line;
    if (!line) {
        return;
    }
    line.enableClass('flag');

    // scroll to expose `line`

    var context = 4;   // how many additional lines to display
    var top = this.eScroll.scrollTop;
    var pos = line.e.offsetTop;
    var topMax = Math.max(pos - line.e.offsetHeight*context, 0);
    var topMin = pos + line.e.offsetHeight*(context+1) - this.eScroll.offsetHeight;
    var topNew = Math.max(topMin, Math.min(topMax, top));

    if (this.timeShown && (scheduler.now() - this.timeShown) < CONTEXT_TIME) {
        // Don't smooth scroll when visible context has not been established
        top = topNew;
    }

    Anim.create(this.e, 'scroll')
        .move(top, topNew, this.setScrollTop.bind(this))
        .start();
};


CodeView.setScrollTop = function (offset) {
    this.eScroll.scrollTop = offset;
};


module.exports = CodeView;
