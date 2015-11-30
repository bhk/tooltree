// mdb_emu.js: emulated MDB (monoglot debugger)
'use strict';

var O = require('observable.js');
var scheduler = require('scheduler.js');
var sampleLua = require('samplelua.js');
var xhttp = require('xhttp.js');

var mdb = {};
module.exports = mdb;


mdb.LOADTIME = 100;   // delay for asynch functions
mdb.RUNTIME = 50;     // time running for stepIn


// bump this to invalidate locals, etc.
var version = O.slot(1);


// observable delay: starts false, becomes true after `ms` milliseconds
//
function Odelay(ms) {
    var b = O.slot(false);
    scheduler.delay(b.setValue.bind(b, true), ms);
    return b;
}

function loadDelay() {
    return Odelay(mdb.LOADTIME);
}


//----------------------------------------------------------------
// mdb.mode
// mdb.action

mdb.mode = O.slot('pause');

mdb.mode.update = mdb.mode.setValue;

mdb.mode.setValue = function (value) {
    this.update(value);
    if (value == 'pause') {
        version.setValue( version.getValue() + 1 );
    }
};

var stackDepth = 5;

var pending;

mdb.action = function (name) {
    var delay = mdb.RUNTIME;
    var delayState = 'pause';

    switch (name) {
    case 'restart':
        appendToConsole('SStarting target process');
        delay = 500;
        break;

    case 'pause':
        delay = 0;
        break;

    case 'stepIn':
        ++stackDepth;
        break;

    case 'stepOut':
        --stackDepth;
        break;

    case 'stepOver':
        delay = 2000;
        break;

    case 'go':
        delayState = 'exit';
        break;

    default:
        throw new Error('bad action code');
    }

    if (delay) {
        if (mdb.mode.getValue() == 'run') {
            throw new Error('bad state: already running at ' + name);
        }
        mdb.mode.setValue('run');
    }

    if (pending) {
        scheduler.cancel(pending);
    }

    pending = scheduler.delay(mdb.mode.setValue.bind(mdb.mode, delayState),
                              delay);
};


//----------------------------------------------------------------
// mdb.stack

var sampleFrames = [
    { name: 'WAITING', what: 'D'},
    { file: 'foo.lua', line: 17, name: 'functionX' },
    { file: 'foo.lua', line: 52, what: 'main'},
    { file: 'foo.lua', line: 12, name: 'functionX' },
    { file: 'bar.lua', line: 5, name: 'functionX' },
    { file: 'bar.lua', line: 11, what: 'main' },
    { file: 'baz.lua', line: 1000, name: '' },
    { file: 'long_file_name.lua', line: 17, name: 'functionX' },
    { file: 'foo.lua', line:102, name: 'a_very_long_function_name' },
    { line: null, what: 'C'}
];


mdb.stack = O.func(function (mode) {
    if (mode == 'down') {
        return undefined;
    }
    return sampleFrames.slice(Math.max(0, sampleFrames.length - stackDepth),
                              sampleFrames.length);
}, mdb.mode);



//----------------------------------------------------------------
// mdb.fetchLocals

var sampleLocals = [
    [
        { name: 'a', value: '"this is a test"' },
        { name: 'b', value: '123' },
        { name: 'c', value: 'true' },
        { name: 'd', value: 'false' },
        { name: 'long_variable_name', value: '"this is a test"' },
        { name: 'e', value: 'table 3' },
        { name: 'f', value: 'function 4' },
        { name: 'g', value: 'userdata 5' },
        { name: 'h', value: 'thread 6' }
    ],
    [
        { name: 'a', value: '"this is a test"' },
        { name: 'b', value: '123' },
        { name: 'c', value: 'true' }
    ]
];


function getLocals(index) {
};


mdb.fetchLocals = function (index) {
    return O.func(function (delay, version) {
        if (!delay(version)) {
            return undefined;
        }
        return mdb.mode.getValue() == 'down'
            ? undefined
            : (sampleLocals[index-1] || sampleLocals[0]);
    }, loadDelay, version);
};


//----------------------------------------------------------------
// mdb.breakpoints

var sampleBreakpoints =  {
    'foo.lua': [12,30,21,28],
    'bar.lua': [14, 7],
    'baz.lua': [42]
};

mdb.breakpoints = O.slot(sampleBreakpoints);


//----------------------------------------------------------------
// mdb.console
// mdb.sendCommand

var sampleConsoleArray = [
    'SStarting target process',
    'Cthis is a command',
    'Ethis is an error',
    'Cthis is a command',
    'R12.45',
    'V"this is a result string"',
    'PThis is a !2table 5!1 and number !234!1.',
    'Vtable 3',
    'Vfunction 4'
];

var sampleConsole = {
    a: sampleConsoleArray,
    len: sampleConsoleArray.length
};

mdb.console = O.slot(sampleConsole);

function appendToConsole(entry) {
    var c = mdb.console.getValue();
    c.a.push(entry);
    mdb.console.setValue({ a:c.a, len: c.len + 1});
}

mdb.sendCommand = function (cmd) {
    appendToConsole('C' + cmd);
    appendToConsole('V12');
};


//----------------------------------------------------------------
// mdb.fetchTablePairs

var tablePairs = {
    dflt: [
        ['"abc"', '"short string"'],
        ["1", 'table 3'],
        ["2", 'table 4']
    ],

    '1': {error: 'stale'},

    '2': [],

    '3': [ ['"abc"', '12'],
           ['"x y"', '"abc"'],
           ['12', '"def"'],
           ['true', 'false'],
           ['"xyz"', 'table 2'],
           ['table 3', 'table 5'] ],

    '4': [
        ['"abc"', 'function 11'],
        ['"def"', '"short string"'],
        ['"this is a longer string longer string longer string longer string longer string longer string longer string"', '123.4'],
        ['table 3', 'table 4']
    ],

    '5': { error: 'stale' }
};


mdb.fetchTablePairs = function (desc) {
    var id = desc.match(/\d*$/)[0];

    return O.func(function (delay, version) {
        if (!delay(version)) {
            return undefined;
        }
        return tablePairs[id] || tablePairs.dflt;
    }, loadDelay, version);

};


//----------------------------------------------------------------
// mdb.fetchSource


function rep(str, reps) {
    var out = '';
    for (var n = reps; n >= 0; --n) {
        out += str;
    }
    return out;
}

var sampleSources = {
    'foo.lua': sampleLua.text,
    'bar.lua': sampleLua.lines.slice(42, 53).join('\n'),
    'baz.lua': rep(sampleLua.text, 20)
};


mdb.fetchSource = function (filename) {
    var text = sampleSources[filename] || sampleSources['foo.lua'];
    text = '-- ' + filename + '\n\n' + text;

    return O.func(function (after) {
        if (!after) {
            return undefined;
        }
        return text;
    }, loadDelay());
};


//----------------------------------------------------------------
// mdb.openValue

// to be overridden by test harness
mdb.openValue = function () {};
