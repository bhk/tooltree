// highlight.js: Syntax highlighting

'use strict';

// JavaScript issues: There appears to be no efficient and easy way in
// JavaScript to search the contents of a string starting at an arbitrary
// offset, as you can with Lua's `string.match`.  We can set the
// `regexp.lastIndex` before calling `.exec()`, which will skip an initial
// portion of the string but search the entire remainder of the string --
// `^` cannot be used to anchor at `lastIndex`; `^` matches only at the
// beginning of the *string*.  Using substr() + exec() would provide
// something close to the desired functionality but perhaps in a very
// inefficient way.  `string.charCodeAt()` could be efficient, but quite
// tedious.  Perhaps this could be made reasonably easy with the aid of a
// parser generator library.
//
// The approach used here is to call `regexp.exec()` after setting
// `regexp.lastIndex` to match tokens.  This starts as a given point in a
// the string and matches in a non-anchored manner, which is fine for
// identifying tokens. We then extract the matched substring and use
// *anchored* regexps to distinguish keywords (e.g. "end") from other
// identifiers (e.g. "bend") and other types.  Any characters skipped over
// by the non-anchored match are condsidered `text`.

var Class = require ('class.js');


var Highlight = Class.subclass();


// `nodeCtor(type, text)` is a function that constructs a value given the
// matched text and the type that has been assigned to it:
//
//    'keyword'    language keywords
//    'comment'    single- or multi-line comments
//    'number'     numeric constant
//    'string'     string literal
//    'text'       other text (none of the above)
//
Highlight.initialize = function (nodeCtor) {
    this.nodeCtor = nodeCtor;
};


// Reset parsing state, so highlighter can be reused for another file.
//
Highlight.reset = function () {
    this.modeEnd = null;
};


// Parse line into syntax elements. Each element is passed to its associated
// callback. The return value is an array of all callback results.
//
Highlight.doLine = function (line) {
    var m;
    var o = [];
    var text = "";
    var nodeCtor = this.nodeCtor;

    function emit(type, str) {
        o.push(nodeCtor(type, str));
    }

    function flushText() {
        if (text !== '') {
            emit('text', text);
            text = '';
        }
    }

    // This expression should match all of the next token, and maybe some
    // non-tokens.  The matched substring will be later tested with
    // testers/matchers.
    var tokenRE = /0[xX][0-9A-Fa-f]+|(\d+\.?|\.\d)\d*([Ee][-+]?\d+)?|[\w_]+|--.*|['"].*|\[=*\[.*/g;

    // tester should quickly fail for tokens that do not match
    var testers = {
        keyword: /^[a-zA-Z_]/,
        string: /^['"]|^\[=*\[/,
        number: /^\.?\d/,
        comment: /^--/
    };

    var matchers = {
        keyword: /^(and|break|do|else(if)?|end|false|function|goto|i[fn]|local|nil|not|or|repeat|return|then|true|until|while)$/,
        number: /^0[xX][0-9A-Fa-f]+|(\d+\.?|\.\d)\d*([eE][-+]?\d+)?(?![\.\w])/,
        string: /^\[(=*)\[.*?\]\1\]|^'([^'\\]|\\.)*'|^"([^"\\]|\\.)*"/,
        comment: /^--\[(=*)\[.*?\]\1\]|^--(?!\[=*\[).*/
    };

    var pos = 0;

    if (this.modeEnd) {
        // in a multi-line mode... look for end
        m = this.modeEnd.exec(line);
        if (!m) {
            pos = line.length;
        } else {
            pos = m.index + m[0].length;
            this.reset();
        }
        emit(this.modeType, line.substr(0, pos));
    }

    for ( ; pos < line.length; ) {
        // "resume" at pos"
        tokenRE.lastIndex = pos;
        var tokenMatch = tokenRE.exec(line);
        if (!tokenMatch) {
            text += line.substr(pos);
            break;
        }

        text += line.substr(pos, tokenMatch.index-pos);
        pos = tokenMatch.index;
        var token = tokenMatch[0];
        var type = null;

        m = null;
        for (var k in testers) {
            if (testers[k].test(token)) {
                m = matchers[k].exec(token);
                type = k;
                break;
            }
        }

        if (!m && (type == "string" || type == "comment")) {
            // start of multi-line long string

            m = /^-?-?\[(=*)\[.*/.exec(token);
            if (m) {
               this.modeEnd = new RegExp('\]' + m[1] + '\]');
               this.modeType = type;
            }
        }

        if (m) {
            flushText();
            emit(type, m[0]);
            pos += m[0].length;
        } else {
            text += token;
            pos += token.length;
        }
    }
    flushText();

    return o;
};


module.exports = Highlight;
