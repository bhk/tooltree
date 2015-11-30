// ECMAScript6-style map object
'use strict';

function Map() {
    this.keys = [];
    this.values = [];
    this.prevKey = undefined;
    this.prevIndex = -1;
};

Map.prototype = Map;


Map.find = function (key) {
    if (key === this.prevKey) {
        return this.prevIndex;
    }
    this.prevKey = key;
    return this.prevIndex = this.keys.indexOf(key);
};


Map.get = function (key) {
    return this.values[this.find(key)];
};


Map.make = function (key, ctor) {
    var index = this.find(key);
    if (index < 0) {
        index = this.keys.push(key) - 1;
        this.prevIndex = index;
        return this.values[index] = ctor();
    }
    return this.values[index];
};


Map.set = function (key, value) {
    var index = this.find(key);
    if (index < 0) {
        index = this.keys.push(key) - 1;
        this.prevIndex = index;
    }
    this.values[index] = value;
};


Map.has = function (key, value) {
    return this.find(key) >= 0;
};


Map.delete = function (key) {
    var index = this.find(key);
    if (index >= 0) {
        var k = this.keys.pop();
        var v = this.values.pop();
        if (index < this.keys.length) {
            this.keys[index] = k;
            this.values[index] = v;
        }
        this.prevIndex = this.keys.length-1;
        this.prevKey = this.keys[this.prevIndex];
    }
};


Map.forEach = function (cb) {
    for (var index = this.keys.length; --index >=0; ) {
        this.prevIndex = index;
        this.prevKey = this.keys[index];
        cb(this.values[index], this.prevKey, this);
    }
};


Object.defineProperty(Map, 'size', {
    get: function () {
        return this.keys.length;
    }
});


module.exports = Map;
