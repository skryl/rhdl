import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

async function ensureTerminalOpen(page) {
  await page.waitForSelector('#terminalPanel', { state: 'attached', timeout: 20000 });
  await page.waitForSelector('#terminalToggleBtn', { state: 'attached', timeout: 20000 });
  const hidden = await page.$eval('#terminalPanel', (panel) => !!panel.hidden);
  if (hidden) {
    await page.click('#terminalToggleBtn');
  }
  await page.waitForFunction(() => {
    const panel = document.querySelector('#terminalPanel');
    return !!panel && panel.hidden === false;
  }, null, { timeout: 20000 });
}

async function runTerminalCommand(page, command, expectedMarker, timeoutMs = 60000) {
  await page.fill('#terminalInput', command);
  await page.click('#terminalRunBtn');
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    const output = await page.textContent('#terminalOutput');
    const text = String(output || '');
    const commandPos = text.lastIndexOf(`$ ${command}`);

    if (commandPos >= 0) {
      const section = text.slice(commandPos);
      if (section.includes(expectedMarker)) {
        return;
      }
      if (section.toLowerCase().includes('error:')) {
        throw new Error(`Terminal command failed for "${command}":\n${section.slice(0, 600)}`);
      }
    }

    await page.waitForTimeout(200);
  }

  const tail = String(await page.textContent('#terminalOutput') || '').slice(-1200);
  throw new Error(`Timed out waiting for terminal marker "${expectedMarker}" after command "${command}".\nTail:\n${tail}`);
}

test('terminal mirb supports one-shot and session flows', { timeout: 300000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err) {
    t.skip('Playwright is not installed (run: `cd web && npm install`)');
    return;
  }

  const webRoot = resolveWebRoot(import.meta.url);
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
      const text = msg.text();
      if (text.includes('Failed to load resource: the server responded with a status of 404')) {
        return;
      }
      consoleErrors.push(text);
    }
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });
  await ensureTerminalOpen(page);

  await runTerminalCommand(page, 'irb 6 * 7', '=> 42');
  await runTerminalCommand(page, 'mirb', 'mirb session started');
  await runTerminalCommand(page, 'n = 10', '=> 10');
  await runTerminalCommand(page, 'n + 5', '=> 15');
  await runTerminalCommand(page, 'exit', 'mirb session closed');
  await runTerminalCommand(page, 'irb 9 - 4', '=> 5');

  const terminalOutput = await page.textContent('#terminalOutput');
  assert.doesNotMatch(terminalOutput || '', /mirb execution timed out/);
  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
