'use strict';

function randomToken(len) {
    if (typeof crypto == "object" && crypto.getRandomBytes) {
        // Chrome, Mozilla
        var buf = new Uint8Array(len);
        return btoa(crypto.getRandomValues(buf)).substr(0, len)
    }

    var str = '';
    for (var n = 0; n < len; ++n) {
        var v = Math.random() * 64;
        v = (v < 26 ? 65 + v :
             v < 52 ? 97 - 26 + v :
             v < 62 ? 48 - 52 + v :
             v == 62 ? 43 : 47);
        str += String.fromCharCode(v);
    }
    return str;
}

module.exports = randomToken;
