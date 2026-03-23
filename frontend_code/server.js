const http = require('http');
const fs = require('fs');
const path = require('path');

const DEFAULT_PORT = Number(process.env.PORT || 5500);
const ROOT = __dirname;

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon'
};

function send(res, statusCode, content, contentType = 'text/plain; charset=utf-8') {
  res.writeHead(statusCode, {
    'Content-Type': contentType,
    'Cache-Control': 'no-store'
  });
  res.end(content);
}

function resolvePath(urlPath) {
  let cleanPath = decodeURIComponent(urlPath.split('?')[0]);
  if (cleanPath === '/') cleanPath = '/index.html';
  const fullPath = path.normalize(path.join(ROOT, cleanPath));
  if (!fullPath.startsWith(ROOT)) return null;
  return fullPath;
}

const server = http.createServer((req, res) => {
  const filePath = resolvePath(req.url || '/');
  if (!filePath) return send(res, 400, 'Bad request');

  fs.stat(filePath, (statErr, stat) => {
    if (statErr) return send(res, 404, 'Not found');

    const finalPath = stat.isDirectory() ? path.join(filePath, 'index.html') : filePath;
    fs.readFile(finalPath, (readErr, data) => {
      if (readErr) return send(res, 404, 'Not found');
      const ext = path.extname(finalPath).toLowerCase();
      send(res, 200, data, MIME_TYPES[ext] || 'application/octet-stream');
    });
  });
});

function startServer(port) {
  server.listen(port, () => {
    console.log(`ALM frontend server running at http://localhost:${port}`);
  });
}

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    const nextPort = Number((server.address() && server.address().port) || DEFAULT_PORT) + 1;
    console.log(`Port in use, retrying on http://localhost:${nextPort}`);
    setTimeout(() => startServer(nextPort), 100);
    return;
  }
  throw err;
});

startServer(DEFAULT_PORT);
