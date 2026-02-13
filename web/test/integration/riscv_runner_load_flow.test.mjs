import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

function setupTestPage(page) {
  const pageErrors = [];
  const consoleErrors = [];

  page.on('pageerror', (err) => {
    const message = String(err?.message || err);
    pageErrors.push(message);
  });

  page.on('console', (msg) => {
    if (msg.type() !== 'error') {
      return;
    }
    const text = msg.text();
    if (text.includes('Failed to load resource: the server responded with a status of 404')) {
      return;
    }
    consoleErrors.push(text);
  });

  return { pageErrors, consoleErrors };
}

async function loadRunner(page, runnerId) {
  await page.waitForFunction((id) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === id);
  }, runnerId, { timeout: 120000 });

  await page.selectOption('#runnerSelect', runnerId);
  await page.click('#loadRunnerBtn');

  await page.waitForFunction((id) => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    const normalized = String(text).toLowerCase();
    const normalizedId = String(id).toLowerCase();
    return normalized.includes(normalizedId) || normalized.includes('risc-v');
  }, runnerId, { timeout: 120000 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });
}

function getEventLog(page) {
  return page.$eval('#eventLog', (el) => el?.textContent || '');
}

function getMemoryDumpPreText(page) {
  return page.$eval('#memoryDump', (el) => {
    const pre = el?.shadowRoot?.querySelector('#memoryDumpPre');
    return pre?.textContent || '';
  });
}

function getDisplayText(page) {
  return page.$eval('#apple2TextScreen', (el) => el?.textContent || '');
}

function getSimCycle(page) {
  return page.$eval('#simStatus', (el) => {
    const text = String(el?.textContent || '');
    const match = text.match(/Cycle\s+(\d+)/);
    return match ? Number.parseInt(match[1], 10) : -1;
  });
}

test('riscv runner loads default kernel, memory, uart and simulation', { timeout: 220000 }, async (t) => {
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
  const { pageErrors, consoleErrors } = setupTestPage(page);

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  await page.selectOption('#backendSelect', 'interpreter');
  await page.dispatchEvent('#backendSelect', 'change');

  await loadRunner(page, 'riscv');

  await page.waitForFunction(() => {
    const log = document.querySelector('#eventLog')?.textContent || '';
    return log.includes('Loaded default bin (main)') && log.includes('./assets/fixtures/riscv/software/bin/kernel.bin');
  }, null, { timeout: 30000 });

  const eventLog = await getEventLog(page);
  assert.match(eventLog, /Loaded default bin \(main\).*kernel\.bin/);
  assert.equal(
    eventLog.includes('Default bin load failed or unsupported for space "main"'),
    false,
    'default bin load should be handled via runner memory API'
  );

  await page.click('[data-tab="memoryTab"]');
  await page.fill('#memoryStart', '0x80000000');
  await page.fill('#memoryLength', '32');
  await page.click('#memoryRefreshBtn');

  await page.waitForFunction(() => {
    const pre = document.querySelector('#memoryDump')?.shadowRoot?.querySelector('#memoryDumpPre');
    const text = pre?.textContent || '';
    return text.includes('17 B1 00 00 13 01 01 40');
  }, null, { timeout: 30000 });

  const memoryDumpText = await getMemoryDumpPreText(page);
  assert.match(memoryDumpText, /17 B1 00 00 13 01 01 40/);
  assert.match(memoryDumpText, /80000000/);

  await page.click('[data-tab="ioTab"]');
  await page.waitForFunction(() => {
    const text = document.querySelector('#apple2TextScreen')?.textContent || '';
    return text.includes('UART') || text.includes('No UART output yet.');
  }, null, { timeout: 12000 });

  const ioText = await getDisplayText(page);
  assert.match(ioText, /No UART output yet\.|UART/i);

  await page.fill('#stepTicks', '128');
  const before = await getSimCycle(page);
  await page.click('#stepBtn');

  await page.waitForFunction((startCycle) => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    const match = text.match(/Cycle\s+(\d+)/);
    if (!match) {
      return false;
    }
    return Number.parseInt(match[1], 10) > startCycle;
  }, before, { timeout: 120000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
