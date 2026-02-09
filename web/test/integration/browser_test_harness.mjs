import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.bin': 'application/octet-stream',
  '.rom': 'application/octet-stream',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8'
};

function isPathInside(parent, target) {
  const rel = path.relative(parent, target);
  return rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

export async function createStaticServer(rootDir) {
  const server = createServer(async (req, res) => {
    try {
      const rawUrl = req.url || '/';
      const urlPath = decodeURIComponent(rawUrl.split('?')[0]);
      const requestedPath = urlPath === '/' ? '/index.html' : urlPath;
      const absPath = path.resolve(rootDir, `.${requestedPath}`);
      if (!isPathInside(rootDir, absPath)) {
        res.writeHead(403);
        res.end('Forbidden');
        return;
      }

      const body = await readFile(absPath);
      const ext = path.extname(absPath).toLowerCase();
      res.setHeader('Content-Type', MIME[ext] || 'application/octet-stream');
      res.writeHead(200);
      res.end(body);
    } catch (_err) {
      res.writeHead(404);
      res.end('Not found');
    }
  });

  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return server;
}

export function serverBaseUrl(server) {
  const addr = server.address();
  if (!addr || typeof addr === 'string') {
    throw new Error('Unable to determine static server address');
  }
  return `http://127.0.0.1:${addr.port}`;
}

export function resolveWebRoot(metaUrl) {
  return path.resolve(path.dirname(fileURLToPath(metaUrl)), '..', '..');
}
