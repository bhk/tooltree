// xhttp: Transact HTTP
//
// This module provides a function that wrap XMLHttpRequest and smooth over
// some of its oddities and troublesome characteristics.
//
//  - Catch exceptions thrown by XHR methods.
//  - Ensure that the response callback is called *once* on completion.
//  - Ensure that the response callback will not be called after cancellation.
//

function makeQuery(query) {
    if (!query) {
        return '';
    }
    var q = [];
    for (var k in query) {
        var v = query[k];
        q.push(encodeURIComponent(k) + '=' + encodeURIComponent(v));
    }
    return '?' + q.join(';');
}


// Perform a synchronous HTTP request
//    request = string | object          [string => { uri: string }]
//       request.uri = uri to request    [not optional]
//       request.method = HTTP method    [default = 'GET']
//       request.body = body to submit   [default = '']
//       request.query = name/value pairs to encode as a query string
//
//    cb = completion callback [null => still asynch, but no notification]
//         cb(error, data, xhr):
//            error = error object or status code for non-2XX response code
//                 false => success
//            data = xhr.responseText on success; `undefined` on error.
//
// Returns a function that will cancel the pending request if called before
// it completes.
//
function xhttp(req, cb) {
    var xhr = new XMLHttpRequest();
    var xerr;

    function respond() {
        if (cb) {
            var status = xhr.status || 999;
            var e = xerr || (status < 200 || status > 299) && status;
            cb(e, (e ? undefined : xhr.responseText), xhr);
            cb = null;
        }
    }


    if (typeof req == 'string') {
        req = {uri: req};
    }
    req.uri += makeQuery(req.query);

    xhr.onreadystatechange = function () {
        if (xhr.readyState == 4) {
            respond();
        }
    };

    try {
        xhr.open(req.method || 'GET', req.uri, true);
        if (req.headers) {
            for (var hdr in req.headers) {
                xhr.setRequestHeader(hdr, req.headers[hdr]);
            }
        }
        xhr.send(req.body);
    } catch (err) {
        xerr = err;
        respond();
    }

    return xhr.abort.bind(xhr);
}

xhttp.makeQuery = makeQuery;

module.exports = xhttp;
