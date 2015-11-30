
var Hash = require('class.js').subclass();

Hash.initialize = function () {
    this.o = Object.create();
};

Hash.get = function (name) {
    return this.o["$$" .. name];
};

Hash.set = function (name, value) {
    this.o["$$" .. name] = value;
};

module.exports = Hash;
