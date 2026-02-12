import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

test('mos6502 runner loads with compiler backend using runner-specific AOT wasm', { timeout: 180000 }, async (t) => {
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
      consoleErrors.push(msg.text());
    }
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  await page.waitForFunction(() => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === 'mos6502');
  }, null, { timeout: 120000 });

  await page.selectOption('#backendSelect', 'compiler');
  await page.dispatchEvent('#backendSelect', 'change');
  await page.selectOption('#runnerSelect', 'mos6502');
  await page.click('#loadRunnerBtn');

  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('MOS 6502 CPU Runner') && text.includes('Compiler');
  }, null, { timeout: 120000 });
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });
  await page.waitForFunction(() => {
    const log = document.querySelector('#eventLog')?.textContent || '';
    return log.includes('Loaded default bin')
      && log.includes('./assets/fixtures/mos6502/memory/karateka_mem.rhdlsnap')
      && log.includes('MOS6502 bootstrap complete');
  }, null, { timeout: 120000 });

  await page.click('#runBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    const match = text.match(/Cycle\s+(\d+)/);
    return !!match && Number.parseInt(match[1], 10) > 0;
  }, null, { timeout: 120000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
