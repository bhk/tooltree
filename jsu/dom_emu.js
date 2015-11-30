// "Mock" DOM implementation for unit testing
//
// window
// document
// document.createElement
// document.head
// document.body
// document.styleSheets
// <Node>.childNodes
// <Node>.appendChild
// <Node>.removeChild
// <Node>.textContent
// <Node>.addEventListener
// <Node>.removeEventListener
// <StyleSheet>.addRule
// <StyleRule>.selectorText
// <StyleRule>.style
// <Style>.<propertyName>

'use strict';

var Class = require('class.js');

var expect = require('expect.js');

function notSupported(cond) {
    if (cond) {
        expect.fail("not supported", 1);
    }
}


function walk(node, fn) {
    function visit(node) {
        node.childNodes.forEach(function (child) {
            fn(child);
            if (child.childNodes) {
                visit(child);
            }
        });
    }
    visit(node);
}


//--------------------------------

var CSS2Properties = Class.subclass();

var chromeCSSProperties = "alignContent alignItems alignSelf alignmentBaseline background backgroundAttachment backgroundBlendMode backgroundClip backgroundColor backgroundImage backgroundOrigin backgroundPosition backgroundPositionX backgroundPositionY backgroundRepeat backgroundRepeatX backgroundRepeatY backgroundSize baselineShift border borderBottom borderBottomColor borderBottomLeftRadius borderBottomRightRadius borderBottomStyle borderBottomWidth borderCollapse borderColor borderImage borderImageOutset borderImageRepeat borderImageSlice borderImageSource borderImageWidth borderLeft borderLeftColor borderLeftStyle borderLeftWidth borderRadius borderRight borderRightColor borderRightStyle borderRightWidth borderSpacing borderStyle borderTop borderTopColor borderTopLeftRadius borderTopRightRadius borderTopStyle borderTopWidth borderWidth bottom boxShadow boxSizing bufferedRendering captionSide clear clip clipPath clipRule color colorInterpolation colorInterpolationFilters colorProfile colorRendering content counterIncrement counterReset cursor direction display dominantBaseline emptyCells enableBackground fill fillOpacity fillRule filter flex flexBasis flexDirection flexFlow flexGrow flexShrink flexWrap cssFloat floodColor floodOpacity font fontFamily fontKerning fontSize fontStretch fontStyle fontVariant fontVariantLigatures fontWeight glyphOrientationHorizontal glyphOrientationVertical height imageRendering justifyContent kerning left letterSpacing lightingColor lineHeight listStyle listStyleImage listStylePosition listStyleType margin marginBottom marginLeft marginRight marginTop marker markerEnd markerMid markerStart mask maskType maxHeight maxWidth maxZoom minHeight minWidth minZoom objectFit objectPosition opacity order orientation orphans outline outlineColor outlineOffset outlineStyle outlineWidth overflow overflowWrap overflowX overflowY padding paddingBottom paddingLeft paddingRight paddingTop page pageBreakAfter pageBreakBefore pageBreakInside paintOrder pointerEvents position quotes resize right shapeRendering size speak src stopColor stopOpacity stroke strokeDasharray strokeDashoffset strokeLinecap strokeLinejoin strokeMiterlimit strokeOpacity strokeWidth tabSize tableLayout textAlign textAnchor textDecoration textIndent textLineThroughColor textLineThroughMode textLineThroughStyle textLineThroughWidth textOverflow textOverlineColor textOverlineMode textOverlineStyle textOverlineWidth textRendering textShadow textTransform textUnderlineColor textUnderlineMode textUnderlineStyle textUnderlineWidth top transition transitionDelay transitionDuration transitionProperty transitionTimingFunction unicodeBidi unicodeRange userZoom vectorEffect verticalAlign visibility webkitAnimation webkitAnimationDelay webkitAnimationDirection webkitAnimationDuration webkitAnimationFillMode webkitAnimationIterationCount webkitAnimationName webkitAnimationPlayState webkitAnimationTimingFunction webkitAppRegion webkitAppearance webkitAspectRatio webkitBackfaceVisibility webkitBackgroundClip webkitBackgroundComposite webkitBackgroundOrigin webkitBackgroundSize webkitBorderAfter webkitBorderAfterColor webkitBorderAfterStyle webkitBorderAfterWidth webkitBorderBefore webkitBorderBeforeColor webkitBorderBeforeStyle webkitBorderBeforeWidth webkitBorderEnd webkitBorderEndColor webkitBorderEndStyle webkitBorderEndWidth webkitBorderFit webkitBorderHorizontalSpacing webkitBorderImage webkitBorderRadius webkitBorderStart webkitBorderStartColor webkitBorderStartStyle webkitBorderStartWidth webkitBorderVerticalSpacing webkitBoxAlign webkitBoxDecorationBreak webkitBoxDirection webkitBoxFlex webkitBoxFlexGroup webkitBoxLines webkitBoxOrdinalGroup webkitBoxOrient webkitBoxPack webkitBoxReflect webkitBoxShadow webkitClipPath webkitColumnBreakAfter webkitColumnBreakBefore webkitColumnBreakInside webkitColumnCount webkitColumnGap webkitColumnRule webkitColumnRuleColor webkitColumnRuleStyle webkitColumnRuleWidth webkitColumnSpan webkitColumnWidth webkitColumns webkitFilter webkitFontFeatureSettings webkitFontSizeDelta webkitFontSmoothing webkitHighlight webkitHyphenateCharacter webkitLineBoxContain webkitLineBreak webkitLineClamp webkitLocale webkitLogicalHeight webkitLogicalWidth webkitMarginAfter webkitMarginAfterCollapse webkitMarginBefore webkitMarginBeforeCollapse webkitMarginBottomCollapse webkitMarginCollapse webkitMarginEnd webkitMarginStart webkitMarginTopCollapse webkitMask webkitMaskBoxImage webkitMaskBoxImageOutset webkitMaskBoxImageRepeat webkitMaskBoxImageSlice webkitMaskBoxImageSource webkitMaskBoxImageWidth webkitMaskClip webkitMaskComposite webkitMaskImage webkitMaskOrigin webkitMaskPosition webkitMaskPositionX webkitMaskPositionY webkitMaskRepeat webkitMaskRepeatX webkitMaskRepeatY webkitMaskSize webkitMaxLogicalHeight webkitMaxLogicalWidth webkitMinLogicalHeight webkitMinLogicalWidth webkitPaddingAfter webkitPaddingBefore webkitPaddingEnd webkitPaddingStart webkitPerspective webkitPerspectiveOrigin webkitPerspectiveOriginX webkitPerspectiveOriginY webkitPrintColorAdjust webkitRtlOrdering webkitRubyPosition webkitTapHighlightColor webkitTextCombine webkitTextDecorationsInEffect webkitTextEmphasis webkitTextEmphasisColor webkitTextEmphasisPosition webkitTextEmphasisStyle webkitTextFillColor webkitTextOrientation webkitTextSecurity webkitTextStroke webkitTextStrokeColor webkitTextStrokeWidth webkitTransform webkitTransformOrigin webkitTransformOriginX webkitTransformOriginY webkitTransformOriginZ webkitTransformStyle webkitTransition webkitTransitionDelay webkitTransitionDuration webkitTransitionProperty webkitTransitionTimingFunction webkitUserDrag webkitUserModify webkitUserSelect webkitWritingMode whiteSpace widows width wordBreak wordSpacing wordWrap writingMode zIndex zoom";

chromeCSSProperties.match(/[^ ]+/g).forEach(function (name) {
    CSS2Properties[name] = '';
});


//--------------------------------

var StyleRule = Class.subclass();

var CSSStyleRule = StyleRule.subclass();

CSSStyleRule.initialize = function (sel, text) {
    notSupported(text !== '');
    this.style = CSS2Properties.create();
    this.selectorText = sel;
};


//--------------------------------
// See http://www.w3.org/TR/cssom/#the-stylesheet-interface

var StyleSheet = Class.subclass();


var CSSStyleSheet = StyleSheet.subclass();


CSSStyleSheet.initialize = function () {
    this.cssRules = [];
    this.disabled = false;
};


CSSStyleSheet.insertRule = function (rule, index) {
    notSupported(index != this.cssRules.length);
    var m = rule.match(/ *(.*?) *\{ *(.*?) *\}/);
    this.cssRules.push(CSSStyleRule.create(m[1], m[2]));
    return index;
};



//--------------------------------

var Node = Class.subclass();

Node.initialize = function () {
    this.childNodes = [];
    this.listeners = [];
};


Node.removeChild = function (child) {
    var index = this.childNodes.indexOf(child);
    expect.assert(index >= 0);
    this.childNodes.splice(index, 1);
    this.parentNode = null;
};


Node.appendChild = function (child) {
    if (child.parentNode) {
        child.parentNode.removeChild(child);
    }
    child.parentNode = this;
    this.childNodes.push(child);

    return child;
};


Node.addEventListener = function (name, fn, capture) {
    this.listeners.push([name, fn, capture]);
};


Node.removeEventListener = function (name, fn, capture) {
    for (var index in this.listeners) {
        var el = this.listeners[index];
        if (el[0] === name && el[1] === fn && el[2] === capture) {
            this.listeners.splice(index, 1);
            return;
        }
    }
};


Object.defineProperty(Node, 'textContent', {
    get: function () {
        var text = '';
        walk(this, function visit(node) {
            if (node.$text) {
                text += node.$text;
            }
        });
        return text;
    },
    set: function (text) {
        notSupported(text !== '');
        this.childNodes.splice(0, this.childNodes.length);
    }
});


//--------------------------------

var Element = Node.subclass();

Element.initialize = function (tagName) {
    Node.initialize.call(this);
    this.tagName = tagName;
    this.className = '';

    if (tagName == 'style') {
        this.$sheet = CSSStyleSheet.create();
    }

    this.style = CSS2Properties.create();
};


//--------------------------------

var Text = Node.subclass();


Text.initialize = function (str) {
    Node.initialize.call(this);
    this.$text = String(str);
};


//--------------------------------

var Document = Node.subclass();

Document.initialize = function () {
    Node.initialize.call(this);

    var html = Element.create('html');
    this.appendChild(html);

    this.head = html.appendChild(Element.create('head'));
    this.body = html.appendChild(Element.create('body'));
};


Object.defineProperty(Document, 'textContent', {
    value: null
});


Document.createElement = function (tagName) {
    return Element.create(tagName);
};


Document.createTextNode = function (str) {
    return Text.create(str);
};


Object.defineProperty(Document, 'styleSheets', {
    // Create a new getter for the property
    get: function () {
        var sheets = [];
        walk(this, function visit(node) {
            if (node.$sheet) {
                sheets.push(node.$sheet);
            }
        });
        return sheets;
    }
});


//--------------------------------
// Browser globals
//--------------------------------

global.window = global.window || global;
global.document = Document.create();

// so 'instanceof' will work...
window.Node = Node.constructor;
window.Element = Element.constructor;


//--------------------------------
// quick self-test

var d = Document.create();
var styleElem = d.createElement('style');
d.head.appendChild(styleElem);
var sheet = d.styleSheets[d.styleSheets.length - 1];

expect.assert(sheet.cssRules instanceof Array);

expect.eq(0, sheet.insertRule('p {}', 0));
var r = sheet.cssRules[0];

expect.eq(r.selectorText, 'p');
