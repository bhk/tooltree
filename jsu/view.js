// E: dynamic element styling

'use strict';

var Class = require('class.js');
var O = require('observable.js');

var View = Class.subclass();


var D = document;
var E = D.createElement.bind(D);


var act = O.createActivator(function (cb) { setTimeout(cb,0); });


D.head.appendChild(E('style'));
var styleSheet = D.styleSheets[D.styleSheets.length - 1];


// Dynamically create a style sheet rule
//
function createRule(selector) {
    var index = styleSheet.cssRules.length;
    styleSheet.insertRule(selector + ' {}', index);
    return styleSheet.cssRules[index];
}


var allNames = Object.create(null);

// Return a name different from all previous results
//
function getUniqueName(name) {
    while (allNames[name]) {
        // append or increment number
        var m = name.match(/(.*?)(\d*)$/);
        name = m[1] + (1 + (+m[2] || 1));
    }
    allNames[name] = true;
    return name;
}


// Memoize a function that accepts a single string argument
//
function memoize(fn) {
    var cache = Object.create(null);
    return function (arg) {
        if (! (arg in cache)) {
            return cache[arg] = fn(arg);
        }
        return cache[arg];
    };
}


var styleObject = E('div').style;
var prefixes = [ 'webkit', 'Moz', 'ms', 'css' ];

// Convert generic JavaScript-style property name to browser-supported form.
// E.g.   "boxSizing" -> "MozBoxSizing"
//
function normalizeName(name) {
    for (var p = name, index = 0; p; ) {
        if (p in styleObject) {
            return p;
        }
        p = prefixes[index++];
        if (p) {
            p +=  name[0].toUpperCase() + name.substr(1);
        }
    }

    console.log('CSS property not supported: ' + name);
    return name;
};

normalizeName = memoize(normalizeName);


// Convert generic CSS property name to browser-specific CSS syntax
// E.g.   "boxSizing" -> "-moz-box-sizing"
//
function cssName(name) {
    return normalizeName(name)
        .replace(/^cssFloat$/, 'float')
        .replace(/([A-Z])/g, '-$1').toLowerCase()
        .replace(/^(webkit|ms)/, '-$1');
}


function replacePropWithCSS(_, name) {
    return cssName(name);
}


// Convert numbers to "px" units and replace "#{jsPropName}" with browser-specific
// CSS syntax.
//
function normalizeValue(value) {
    if (typeof value == 'string') {
        return value.replace(/#\{(.*?)\}/g, replacePropWithCSS);
    } else if (typeof value == 'number') {
        return value + 'px';
    } else if (value == undefined) {
        return '';
    } else {
        throw new Error('View: invalid property value: ' + value);
    }
}


// Scan a property description, adding CSS property assignments to `rules`
// and `$` properties to `obj`.
//
// `props`: Propery description (see view.txt)
// `obj`: object to receive '$' properties (null => ignore '$' properties)
// `rules`: array to receive stylesheet rules
// `selector`: selector prefix to apply to all stylesheet rules
//
// Return value = `rules` array.  Each rule = {
//        selector = <selecor text>,
//        names = <array of normalized property names>,
//        values = <array of normalized property values>
//    }
//
function scanProps(props, obj, rules, selector) {
    var rule = null;  // create only if needed
    var mods = [];

    // sort properties and normalize keys and values

    Object.keys(props).sort().forEach(function (key) {
        var value = props[key];
        if (key.match(/^[A-Za-z0-9-]+$/)) {
            // CSS property
            if (!rule) {
                rule = { selector: selector, names: [], values: [] };
                rules.push(rule);
            }
            rule.names.push(normalizeName(key));
            rule.values.push(normalizeValue(value));
        } else if (key.match(/^\$/)) {
            // non-CSS property
            if (obj) {
                obj[key] = value;
            }
        } else if (/\?/.test(key)) {
            mods.push(['{' + key + '}', value]);
        } else {
            throw new Error('View: unsupported property: ' + key);
        }
    });

    for (var ndx = 0; ndx < mods.length; ++ndx) {
        var mod = mods[ndx];
        scanProps(mod[1], null, rules, selector + mod[0]);
    }
}


// Apply all properties listed in `rule` into `style`
//
function applyRule(rule, style) {
    var values = rule.values,
        names = rule.names;
    for (var ndx = 0; ndx < names.length; ++ndx) {
        style[names[ndx]] = values[ndx];
    }
}


// Create a new stylesheet rule.
//
function addRule(baseSelector, rule) {
    var prefix = baseSelector;
    var suffix = '';
    var sel = rule.selector.replace(/{([^?}]*)\?([^}]*)}/g, function (_, a, b) {
        prefix = a + prefix;
        suffix += b;
        return '';
    });

    applyRule(rule, createRule(prefix + sel + suffix).style);
}


// Create a new stylesheet rule for each entry in rules[].
//
function addRulesToSheet(rules, baseSelector) {
    for (var ndx = 0; ndx < rules.length; ++ndx) {
        addRule(baseSelector, rules[ndx]);
    }
}


// Apply rules to an individual element.  Top-level properties are applied
// directly to the element's `.style` property.  For modifiers, we create a
// stylesheet rule that uses an ID-based selector for the element. The `id`
// argument provides a suggestion for the ID, if non-null.
//
function applyRulesToElement(rules, e, id) {
    for (var ndx = 0; ndx < rules.length; ++ndx) {
        var rule = rules[ndx];

        if (rule.selector == '') {
            applyRule(rule, e.style);
        } else {
            e.id || (e.id = getUniqueName(id || '1'));
            addRule('#' + e.id, rule);
        }
    }
}


// Scan content items.
//
// items = Array of items, each of which is one of the following:
//         - View instance (to be appended)
//         - DOM Node (to be appended)
//         - String/Number (to be appended as a text node)
//         - Properties object (generating rules and/or object properties)
//         - Array of items
// nodes = array to be filled with content nodes
// rules = array to be filled with stylsheet rules (see scanProps)
// obj = object to receive '$...' properties
//
function scanItems(items, nodes, rules, obj) {
    for (var ndx = 0; ndx < items.length; ++ndx) {
        var item = items[ndx];
        if (item instanceof Array) {
            scanItems(item, nodes, rules, obj);
        } else if (View.hasInstance(item)) {
            nodes.push(item.e);
        } else if (item instanceof Node) {
            nodes.push(item);
        } else if (item instanceof Object) {
            scanProps(item, obj, rules, '');
        } else if (item != null) {
            nodes.push( D.createTextNode(item) );
        }
    }
}


//----------------------------------------------------------------
// View
//----------------------------------------------------------------


View.prefix = '_';


View.$tag = 'div';


View.subclassInitialize = function () {
    // collect contents, rules, and '$' properties
    var rules = [];
    var nodes = [];
    scanItems(arguments, nodes, rules, this);

    if (nodes.length > 0) {
        throw new Error('content elements passed to View.subclass');
    }

    var cls = this.prefix + getUniqueName(this.$class || 'c');
    var sel = (this.selector || '') + '.' + cls;

    this.selector = sel;
    this.className = sel.substr(1).replace(/\./g, ' ');

    addRulesToSheet(rules, sel);
};


View.initialize = function () {
    this.e = null;
    this.append.apply(this, arguments);
    if (this.postInit) {
        this.postInit.call(this);
    }
};


View.append = function () {
    // collect contents, rules, and '$' properties
    var rules = [];
    var nodes = [];
    scanItems(arguments, nodes, rules, this);

    // create element
    if (!this.e) {
        this.e = E(this.$tag);
        if (this.className) {
            this.e.className = this.className;
        }
    }

    // apply stylesheet rules
    if (rules.length) {
        applyRulesToElement(rules, this.e, this.$id);
    }

    // append contents
    if (nodes.length) {
        nodes.forEach(this.e.appendChild.bind(this.e));
    }
};


View.enableClass = function (cls, bOn) {
    bOn = bOn || (arguments.length < 2);
    var old = this.e.className;
    var a = ' ' + old + ' ';
    if (bOn) {
        if (a.indexOf(' ' + cls + ' ') < 0) {
            this.e.className = (old && old + ' ') + cls;
        }
    } else {
        var b = a.replace(' ' + cls + ' ', ' ');
        if (a != b) {
            this.e.className = b.substr(1, b.length-2);
        }
    }
    return this;
};


View.enableClasses = function (classes, bOn) {
    var me = this;
    bOn = bOn || (arguments.length < 2);
    classes.replace(/[^ ]+/g, function (name) {
        me.enableClass(name, bOn);
    });
};


View.setContent = function () {
    this.e.textContent = '';
    this.append.apply(this, arguments);
};


// Register a de-registration function with the View instance, returning a new
// de-registration function.
//
View.register = function (dereg) {
    if (!dereg) {
        return dereg;
    }
    var deregs = this.deregs || (this.deregs = []);
    var id = deregs.push(thisDereg) - 1;
    function thisDereg() {
        delete deregs[id];
        dereg();
    };
    return thisDereg;
};


// De-register everything registered with `.register()` except for those that
// have since been individually de-registered.
//
View.destroy = function () {
    if (this.deregs) {
        for (var k in this.deregs) {
            this.deregs[k]();
        }
    }
};


View.activate = function ( /* ... */ ) {
    return this.register(act.activate.apply(act, arguments));
};


View.wrap = function (domNode) {
    var view = this.subclass();
    view.e = domNode;
    return view;
};


View.normalizeName = normalizeName;
View.normalizeValue = normalizeValue;
View.cssName = cssName;
View.scanProps = scanProps;
View.applyRulesToElement = applyRulesToElement;

module.exports = View;
