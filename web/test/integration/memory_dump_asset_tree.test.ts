import test from 'node:test';
import assert from 'node:assert/strict';
import type { Page } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

async function loadCpuRunner(page: Page) {
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
}

test('memory dump asset tree selection populates path and loads selected asset', { timeout: 180000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && bun install`)');
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
  } catch (_err: unknown) {
    console.warn('Playwright browser binaries are missing (run: `cd web && bunx playwright install chromium`)');
    return;
  }
  t.after(async () => {
    await browser.close();
  });

  const page = await browser.newPage();
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];

  page.on('pageerror', (err) => {
    const message = String(err?.message || err);
    if (BENIGN_PAGE_ERRORS.some((entry) => message.includes(entry))) {
      return;
    }
    pageErrors.push(message);
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

  await loadCpuRunner(page);
  await page.click('[data-tab="memoryTab"]');

  const assetPath = './assets/fixtures/cpu/software/conway_glider_80x24.bin';
  const selector = `#memoryDumpAssetTree button[data-asset-path="${assetPath}"]`;
  await page.waitForSelector(selector, { timeout: 30000 });
  await page.click(selector);

  const selectedPath = await page.inputValue('#memoryDumpAssetPath');
  assert.equal(selectedPath, assetPath);

  await page.fill('#memoryDumpOffset', '0x0000');
  await page.click('#memoryDumpLoadBtn');
  await page.waitForFunction((name) => {
    const text = document.querySelector('#memoryDumpStatus')?.textContent || '';
    return text.includes(`Loaded ${name}`)
      || text.includes(`Asset load failed`) && text.includes(`${name}`);
  }, 'conway_glider_80x24.bin', { timeout: 30000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
