// Tiny HTTP server for testing the launcher (port from argv[2]).
const port = Number(process.argv[2] || 8080);
require('http').createServer((q, s) => s.end('ok')).listen(port, '127.0.0.1');
console.log('dummy listening on', port);
