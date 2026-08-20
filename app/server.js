// Minimal zero-dependency static server for the built Flutter web app.
//
// Cache strategy (adapted from the phone-ready playbook for Flutter web):
//   - Flutter's entrypoints are UNHASHED and change on every deploy
//     (index.html, main.dart.js, flutter_bootstrap.js, flutter_service_worker.js,
//     *.json). Serve these `no-cache` so the browser revalidates and every
//     deploy is picked up — this kills the "stale on phone after deploy" bug.
//   - Binary assets (images, fonts, wasm/canvaskit) are safe to cache hard.
//
// Listens on $PORT (Render provides it) and serves ./build/web.

const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, 'build', 'web');
const PORT = process.env.PORT || 8080;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.map': 'application/json; charset=utf-8',
};

function cacheControl(ext) {
  // Unhashed source files change on every deploy -> always revalidate.
  if (ext === '.html' || ext === '.js' || ext === '.mjs' || ext === '.json') {
    return 'no-cache';
  }
  // Images, fonts, wasm: content is stable, cache hard.
  return 'public, max-age=31536000, immutable';
}

const server = http.createServer((req, res) => {
  let urlPath = decodeURIComponent((req.url || '/').split('?')[0]);
  if (urlPath === '/') urlPath = '/index.html';

  // Resolve within ROOT and block path traversal.
  let filePath = path.normalize(path.join(ROOT, urlPath));
  if (filePath !== ROOT && !filePath.startsWith(ROOT + path.sep)) {
    res.writeHead(403);
    return res.end('Forbidden');
  }

  fs.stat(filePath, (err, stat) => {
    if (err || !stat.isFile()) {
      // SPA safety net: unknown non-file routes fall back to index.html.
      filePath = path.join(ROOT, 'index.html');
    }
    const ext = path.extname(filePath).toLowerCase();
    fs.readFile(filePath, (readErr, data) => {
      if (readErr) {
        res.writeHead(404);
        return res.end('Not found');
      }
      res.writeHead(200, {
        'Content-Type': MIME[ext] || 'application/octet-stream',
        'Cache-Control': cacheControl(ext),
      });
      res.end(data);
    });
  });
});

server.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`girltea web serving ${ROOT} on :${PORT}`);
});
