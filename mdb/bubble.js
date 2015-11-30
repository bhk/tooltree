// bubble.js: expandable/collapsible table representation

'use strict';

var View = require('view.js');


var BubbleTab = View.subclass({
    $class: 'bubble-tab',
    cssFloat: 'left',
    position: 'relative',

    background: '#ccc',
    color: '#555',
    padding: '1px 2px 0',
    borderWidth: 0,
    borderRadius: '5px 5px 0 0',

    '?::after': {
        // round the nook to the right of the tab
        content: '""',
        position: 'absolute',
        borderStyle: 'solid',
        borderColor: '#ccc',
        borderWidth: '0px 0px 2px 2px',
        width: 4,
        height: 4,
        right: -4,
        bottom: -2,
        borderBottomLeftRadius: 6
    },

    '?::before': {
        // fill the gap at the top-left of the body
        content: '""',
        position: 'absolute',
        borderStyle: 'solid',
        borderColor: 'transparent',
        borderLeftColor: '#CCC',
        borderWidth: '0 0 8px 8px',
        width: 0,
        height: 0,
        bottom: -7,   // leave overlap for inexact scaling
        left: 0
    },

    '?:only-child': {
        borderRadius: 5,
        paddingBottom: 1,

        '?::before': {
            content: 'none'
        },
        '?::after': {
            content: 'none'
        }
    }
});


var BubbleBody = View.subclass({
    $class: 'bubble-body',
    clear: 'left',
    border: '3px solid #ccc',
    borderRadius: '8px 8px 8px 8px',
    minHeight: 10,
    minWidth: 90
});


var Bubble = View.subclass({
    $class: 'bubble',
    display: 'inline-block',
    font: '12px Helvetica, sans-serif',
    verticalAlign: 'top',
    marginBottom: 1
});


// Usage:
//   Bubble.create({ cssprop: value, ... , $caption: ..., $content: ...});
//
Bubble.postInit = function () {
    this.append( BubbleTab.create(this.$caption) );
    this.activate(function (content) {
        var c = this.e.childNodes[1];
        if (c) {
            this.e.removeChild(c);
        }
        if (content) {
            this.append(BubbleBody.create(content));
        }
    }.bind(this), this.$content);
};


module.exports = Bubble;
