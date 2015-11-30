// Base class for a simplified object system.  See class.txt.

var Class = {};


Class.subclass = function () {
    var c = Object.create(this);
    c.constructor = function () {};  // for `hasInstance`
    c.constructor.prototype = c;
    if (this.subclassInitialize) {
        this.subclassInitialize.apply(c, arguments);
    }
    return c;
};


Class.create = function () {
    var o = Object.create(this);
    var init = this.initialize;
    if (init) {
        init.apply(o, arguments);
    }
    return o;
};


Class.hasInstance = function (obj) {
    return obj instanceof this.constructor;
};


module.exports = Class;
