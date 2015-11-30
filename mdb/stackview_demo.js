var demo = require('demo.js');
var View = require('view.js');
var O = require('observable.js');
var StackView = require('stackview.js');


var sampleFrames = [
    { file: 'foo.lua', line:  1, name: 'functionX' },
    { file: 'foo.lua', line: 12, what: 'main'},
    { line: null, what: 'C'},
    { file: 'foo.lua', line: 31, name: 'functionX' },
    { file: 'foo.lua', line: 32, name: 'functionX' },
    { file: 'foo.lua', line: 36, name: '' },
    { file: 'long_file_name.lua', line: 17, name: 'functionX' },
    { file: 'foo.lua', line:102, name: 'a_very_long_function_name' },
    { file: 'foo.lua', line: 17, name: 'functionX' },
    { file: 'foo.lua', line: 32, name: 'functionX' },
    { file: 'foo.lua', line: 36, name: '' },
    { file: 'long_file_name.lua', line: 17, name: 'functionX' },
    { file: 'foo.lua', line:102, name: 'a_very_long_function_name' },
    { file: 'foo.lua', line: 17, name: 'functionX' }
];


var frames = O.slot(sampleFrames);
var stackView = StackView.create(frames);

demo.init({
    height: 164,
    width: '50%',
    overflow: 'auto'
});

// track activated frame
var selected = View.create({$tag: 'span'});
selected.activate(function (frame) {
   selected.setContent(frame ? frame.index : '-none-');
}, stackView.selection);
demo.log(['Selected: ', selected]);


demo.append(stackView);

demo.addButton('null', frames.setValue.bind(frames, null));
demo.addButton('long', frames.setValue.bind(frames, sampleFrames));
demo.addButton('short', frames.setValue.bind(frames, sampleFrames.slice(0, 2)));
