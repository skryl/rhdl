import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

async function runEditorTerminalCommand(page, command, expectedMarker, timeoutMs = 60000) {
  await page.click('#editorTerminalOutput');
  await page.keyboard.type(command);
  await page.keyboard.press('Enter');

  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    const text = await page.$eval(
      '#editorTerminalOutput',
      (el) => String(el.dataset?.terminalText ?? el.value ?? el.textContent ?? '')
    );
    if (text.includes(expectedMarker)) {
      return;
    }
    if (text.toLowerCase().includes('error:')) {
      throw new Error(`Editor terminal command failed for "${command}":\n${text.slice(0, 800)}`);
    }
    await page.waitForTimeout(200);
  }

  const tail = await page.$eval(
    '#editorTerminalOutput',
    (el) => String(el.dataset?.terminalText ?? el.value ?? el.textContent ?? '').slice(-1200)
  );
  throw new Error(`Timed out waiting for marker "${expectedMarker}" after "${command}".\nTail:\n${tail}`);
}

test('editor tab executes code in mirb and refreshes IO trace view', { timeout: 240000 }, async (t) => {
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

  await page.click('#loadRunnerBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });

  await page.click('[data-tab="editorTab"]');
  await page.waitForFunction(() => {
    const editorTab = document.querySelector('#editorTab');
    return !!editorTab && editorTab.classList.contains('active');
  }, null, { timeout: 20000 });
  await page.waitForSelector('#editorTerminalOutput', { state: 'attached', timeout: 20000 });
  await page.waitForSelector('#editorExecuteBtn', { state: 'attached', timeout: 20000 });

  await runEditorTerminalCommand(page, '6 * 7', '=> 42');

  await page.fill('#editorFallback', '9 - 4');
  await page.click('#editorExecuteBtn');
  await page.waitForFunction(() => {
    const terminalEl = document.querySelector('#editorTerminalOutput');
    const text = String(terminalEl?.dataset?.terminalText ?? terminalEl?.value ?? terminalEl?.textContent ?? '');
    return text.includes('$ irb <editor-buffer>') && text.includes('=> 5');
  }, null, { timeout: 60000 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#editorTraceMeta')?.textContent || '';
    return /Tracing \d+ IO signals/.test(text);
  }, null, { timeout: 60000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
