import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

async function loadCpuRunner(page) {
  await page.waitForFunction(() => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === 'cpu');
  }, null, { timeout: 120000 });

  await page.selectOption('#runnerSelect', 'cpu');
  await page.click('#loadRunnerBtn');

  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('CPU (examples/8bit/hdl/cpu)');
  }, null, { timeout: 120000 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });
}

test('8bit cpu runner auto-loads default bin and logs it', { timeout: 180000 }, async (t) => {
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
  await loadCpuRunner(page);

  const selectedBackend = await page.$eval('#backendSelect', (el) => el.value);
  assert.equal(selectedBackend, 'compiler');

  await page.waitForFunction(() => {
    const stepTicks = document.querySelector('#stepTicks')?.value || '';
    const runBatch = document.querySelector('#runBatch')?.value || '';
    const uiUpdateCycles = document.querySelector('#uiUpdateCycles')?.value || '';
    return stepTicks === '100' && runBatch === '2000' && uiUpdateCycles === '2000';
  }, null, { timeout: 30000 });

  const perfDefaults = await page.evaluate(() => ({
    stepTicks: document.querySelector('#stepTicks')?.value || '',
    runBatch: document.querySelector('#runBatch')?.value || '',
    uiUpdateCycles: document.querySelector('#uiUpdateCycles')?.value || ''
  }));
  assert.equal(perfDefaults.stepTicks, '100');
  assert.equal(perfDefaults.runBatch, '2000');
  assert.equal(perfDefaults.uiUpdateCycles, '2000');

  await page.waitForFunction(() => {
    const logText = document.querySelector('#eventLog')?.textContent || '';
    return logText.includes('Loaded default bin (main)') && logText.includes('conway_glider_80x24.bin');
  }, null, { timeout: 30000 });

  await page.fill('#stepTicks', '12000');
  let foundLiveCell = false;
  for (let i = 0; i < 20; i += 1) {
    await page.click('#stepBtn');
    foundLiveCell = await page.evaluate(() => {
      const screenText = document.querySelector('#apple2TextScreen')?.textContent || '';
      return screenText.includes('#');
    });
    if (foundLiveCell) {
      break;
    }
  }
  assert.equal(foundLiveCell, true, 'expected default glider program to render at least one live cell');

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
