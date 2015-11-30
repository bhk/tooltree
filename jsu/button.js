// Button constructor class

"use strict";

var View = require('view.js');
var scheduler = require('scheduler.js');
var Anim = require('anim.js').newClass(scheduler);
var captureClick = require('eventutils.js').captureClick;


var Button = View.subclass({
    $class: 'button',
    userSelect: 'none',
    boxSizing: 'border-box',

    cssFloat: 'left',
    margin: '1px 2px 2px 2px',
    height: 27,
    width: 26,
    padding: '0px 0px 0px 1px',
    border: '1px solid transparent',
    borderRadius: 14,
    lineHeight: 26,

    // Arial gives more consistent results between Chrome/Mac and Firefox/Mac
    font: 'bold 18px "Arial", sans-serif',
    textAlign: 'center',
    whiteSpace: 'nowrap',

    // disabled
    color: '#a0a0a0',
    transform: 'translate(1px,1px)',
    transition: '#{transform} 0.05s',

    '?.enabled': {
        color: '#000',
        textShadow: '2px 2px 4px rgba(0,0,0,.4)',
        transform: 'none',

        '?:active': {
            transform: 'translate(1px,1px)',
            textShadow: '1px 1px 1px white'
        },

        '?:hover': {
            borderStyle: 'solid',
            borderColor: '#aaa',
            textShadow: 'none',
            backgroundColor: '#e4e4e4',
            boxShadow: '2px 2px 3px rgba(0,0,0,.15)',
            transition: 'none',

            '?:active': {
                boxShadow: '-1px -1px 2px rgba(0,0,0,0.13), 1px 1px 2px rgba(255,255,255,0.9)',
                backgroundColor: 'transparent',
                borderColor: '#777 #AAA #AAA #777'
            }
        }
    }
});


// $onclick = function to call when clicked
// $clickArg = argument to pass to the $onclick
// $title = tooltip
Button.postInit = function ()
{
    if (this.$title) {
        this.e.title = this.$title;
    }
    this.enable(true);

    this.flashAnim = Anim.create(this.e)
        .css({backgroundColor: '#e3f0e3', borderColor: '#adf4b1'})
        .cssTransition({backgroundColor: '', borderColor: ''}, 300)
        .css({transition: ''});
};


Button.enable = function (isEnabled) {
    isEnabled = !!isEnabled;
    if (this.isEnabled == isEnabled) {
        return;
    }
    this.isEnabled = isEnabled;
    this.enableClass('enabled', isEnabled);
    if (isEnabled) {
        this.cancelClick = captureClick(this.e, this.fireClick, this);
    } else {
        this.cancelClick();
    }
};


Button.fireClick = function () {
    if (this.$onclick) {
        this.$onclick(this.$clickArg);
    }
};


// Visually indicate that a button's functionality has been activated by a
// key shortcut.
//
Button.flash = function () {
    this.flashAnim.start();
};


module.exports = Button;
