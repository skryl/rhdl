import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

test('web app core flows run in a real browser session', { timeout: 180000 }, async (t) => {
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
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('Apple II System Runner');
  }, null, { timeout: 120000 });
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });

  await page.click('[data-tab="memoryTab"]');
  await page.click('#loadKaratekaBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#memoryDumpStatus')?.textContent || '';
    return text.includes('Loaded Karateka dump');
  }, null, { timeout: 120000 });

  await page.fill('#memoryResetVector', '0xB82A');
  await page.click('#memoryResetBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#memoryDumpStatus')?.textContent || '';
    return text.includes('Reset complete');
  }, null, { timeout: 120000 });

  const memoryStatusText = await page.textContent('#memoryStatus');
  assert.match(memoryStatusText || '', /Reset complete/);

  await page.evaluate(() => {
    document.querySelector('#runBtn')?.click();
  });
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('RUNNING');
  }, null, { timeout: 120000 });

  await page.evaluate(() => {
    document.querySelector('#pauseBtn')?.click();
  });
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('PAUSED');
  }, null, { timeout: 120000 });

  await page.click('#terminalToggleBtn');
  await page.click('#terminalOutput');
  await page.keyboard.type('status');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => {
    const el = document.querySelector('#terminalOutput');
    const text = String(el?.dataset?.terminalText ?? el?.value ?? el?.textContent ?? '');
    return text.includes('runner=apple2') && /backend=\S+/.test(text);
  }, null, { timeout: 120000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
