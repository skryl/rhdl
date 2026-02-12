import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

test('memory follow-pc auto-scrolls and changed bytes are temporarily highlighted', { timeout: 180000 }, async (t) => {
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
  await page.selectOption('#runnerSelect', 'mos6502');
  await page.click('#loadRunnerBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('MOS 6502 CPU Runner');
  }, null, { timeout: 120000 });

  await page.click('[data-tab="memoryTab"]');
  await page.fill('#memoryLength', '0x10000');
  await page.check('#memoryFollowPc');
  await page.click('#memoryRefreshBtn');

  await page.waitForFunction(() => {
    const view = document.querySelector('#memoryDump');
    const dumpPre = view?.shadowRoot?.querySelector('#memoryDumpPre');
    const disasmPre = view?.shadowRoot?.querySelector('#memoryDisasmPre');
    if (!(dumpPre instanceof HTMLElement) || !(disasmPre instanceof HTMLElement)) {
      return false;
    }
    return dumpPre.scrollTop > 0 && disasmPre.scrollTop > 0;
  }, null, { timeout: 60000 });

  await page.fill('#memoryWriteAddr', '0x0010');
  await page.fill('#memoryWriteValue', '0x41');
  await page.click('#memoryWriteBtn');
  await page.fill('#memoryWriteValue', '0x42');
  await page.click('#memoryWriteBtn');

  await page.waitForFunction(() => {
    const view = document.querySelector('#memoryDump');
    const changed = view?.shadowRoot?.querySelectorAll('.changed-byte')?.length || 0;
    return changed > 0;
  }, null, { timeout: 30000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
