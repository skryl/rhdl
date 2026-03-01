import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Server } from 'node:http';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.ts': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.bin': 'application/octet-stream',
  '.rom': 'application/octet-stream',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8'
};

function isPathInside(parent: string, target: string) {
  const rel = path.relative(parent, target);
  return rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function withExtensionFallback(absPath: string): string[] {
  const ext = path.extname(absPath);
  if (ext) {
    return [absPath];
  }
  return [absPath, `${absPath}.js`, `${absPath}.mjs`, `${absPath}.ts`];
}

export async function createStaticServer(rootDir: string): Promise<Server> {
  const distDir = path.resolve(rootDir, 'dist');

  const server = createServer(async (req, res) => {
    res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
    res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
    try {
      const rawUrl = req.url || '/';
      const urlPath = decodeURIComponent(rawUrl.split('?')[0]);
      const requestedPath = urlPath === '/' ? '/index.html' : urlPath;
      const distPath = path.resolve(distDir, `.${requestedPath}`);
      const rootPath = path.resolve(rootDir, `.${requestedPath}`);
      const candidates = [distPath, rootPath]
        .flatMap((candidate) => withExtensionFallback(candidate));

      for (const absPath of candidates) {
        if (!isPathInside(rootDir, absPath)) {
          continue;
        }
        try {
          const body = await readFile(absPath);
          const ext = path.extname(absPath).toLowerCase();
          res.setHeader('Content-Type', (MIME as Record<string, string>)[ext] || 'application/octet-stream');
          res.writeHead(200);
          res.end(body);
          return;
        } catch (_err: unknown) {
          // Try next candidate.
        }
      }

      res.writeHead(404);
      res.end('Not found');
    } catch (_err: unknown) {
      res.writeHead(404);
      res.end('Not found');
    }
  });

  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', () => resolve()));
  return server;
}

export function serverBaseUrl(server: Server): string {
  const addr = server.address();
  if (!addr || typeof addr === 'string') {
    throw new Error('Unable to determine static server address');
  }
  return `http://127.0.0.1:${addr.port}`;
}

export function resolveWebRoot(metaUrl: string): string {
  return path.resolve(path.dirname(fileURLToPath(metaUrl)), '..', '..');
}
