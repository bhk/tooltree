'use strict';

require('dom_emu.js');
require('settimeout_emu.js');
var expect = require('expect.js');
var CodeView = require('codeview.js');

Element.addEventListener = function () {};

var cv = CodeView.create();
window.setTimeout.flush();

cv.setText('a\nb\nc\n', [1,2,3]);
cv.flagLine(2);
window.setTimeout.flush();

cv.setText(null, undefined);
window.setTimeout.flush();
