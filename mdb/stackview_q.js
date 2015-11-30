require('dom_emu.js');
var StackView = require('stackview.js');

var sampleFrames = [
    { file: 'foo.lua', line:  1, name: 'functionX' },
    { file: 'foo.lua', line: 12, what: 'main'},
    { line: null, what: 'C'}
];

var v = StackView.create(sampleFrames);
