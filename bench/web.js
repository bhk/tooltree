// Simple web server in JavaScript

var http = require('http');
var url = require('url');

var handler = function(req, resp) {
    var u = url.parse(req.url);

    if (req.method === 'GET' && u.pathname === '/hello') {
        resp.writeHead(200, {'content-type': 'text/plain'});
        resp.end('Hello!');
    } else {
        resp.writeHead(404, {'content-type': 'text/html'});
        resp.end('Resource not found');
    }
};

var addr = process.argv[2] || '127.0.0.1:8002';
var hostPort = addr.match(/^([^:]*):?(.*)/);

http.createServer(handler).listen(hostPort[2], hostPort[1] || '127.0.0.1');
console.log('Listening on ' + addr + ' ...');
