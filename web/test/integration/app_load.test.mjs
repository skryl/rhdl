import test from 'node:test';
import assert from 'node:assert/strict';
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

async function createStaticServer(rootDir) {
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

function serverBaseUrl(server) {
  const addr = server.address();
  if (!addr || typeof addr === 'string') {
    throw new Error('Unable to determine static server address');
  }
  return `http://127.0.0.1:${addr.port}`;
}

test('web app loads in browser without uncaught runtime errors', { timeout: 120000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err) {
    t.skip('Playwright is not installed (run: `cd web && npm install`)');
    return;
  }

  const webRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
  const server = await createStaticServer(webRoot);
  t.after(() => {
    server.close();
  });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (_err) {
    t.skip('Playwright browser binaries are missing (run: `cd web && npx playwright install chromium`)');
    return;
  }
  t.after(async () => {
    await browser.close();
  });

  const page = await browser.newPage();
  const pageErrors = [];
  const consoleErrors = [];

  page.on('pageerror', (err) => {
    pageErrors.push(String(err?.message || err));
  });
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });
  await page.waitForTimeout(3000);

  const statusText = await page.textContent('#simStatus');
  assert.ok(statusText && statusText.trim().length > 0, 'sim status should be populated');
  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
