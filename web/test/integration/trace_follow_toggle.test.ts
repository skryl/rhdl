import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  resolveWebRoot,
  serverBaseUrl
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

async function loadApple2Runner(page) {
  await page.click('#loadRunnerBtn');

  await page.waitForFunction(() => {
    const runner = document.querySelector('#runnerStatus')?.textContent || '';
    const sim = document.querySelector('#simStatus')?.textContent || '';
    return runner.includes('Apple II System Runner') && sim.includes('Cycle 0');
  }, null, { timeout: 120000 });
}

test('run-loop follower updates stay disabled until tracing is enabled', { timeout: 180000 }, async (t) => {
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
    const message = String(err?.message || err);
    if (BENIGN_PAGE_ERRORS.some((entry) => message.includes(entry))) {
      return;
    }
    pageErrors.push(message);
  });
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });
  await loadApple2Runner(page);

  await page.fill('#runBatch', '5');
  await page.fill('#uiUpdateCycles', '10');

  await page.click('#runBtn');
  await page.waitForFunction(() => {
    const ux = window.__RHDL_UX_STATE__;
    return !!ux && ux.running === true && Number(ux.cycle) >= 40;
  }, null, { timeout: 120000 });

  const pendingWhileTraceDisabled = await page.evaluate(() => Number(window.__RHDL_UX_STATE__?.uiCyclesPending || 0));
  assert.ok(
    pendingWhileTraceDisabled >= 20,
    `expected pending cycles to accumulate with trace disabled, got ${pendingWhileTraceDisabled}`
  );

  await page.click('#pauseBtn');
  await page.waitForFunction(() => {
    const ux = window.__RHDL_UX_STATE__;
    return !!ux && ux.running === false;
  }, null, { timeout: 120000 });

  await page.click('#traceStartBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#traceStatus')?.textContent || '';
    return text.includes('Trace enabled');
  }, null, { timeout: 120000 });

  const baselineCycle = await page.evaluate(() => Number(window.__RHDL_UX_STATE__?.cycle || 0));
  await page.click('#runBtn');
  await page.waitForFunction((baseline) => {
    const ux = window.__RHDL_UX_STATE__;
    return !!ux
      && ux.running === true
      && Number(ux.cycle) >= (Number(baseline) + 40)
      && Number(ux.uiCyclesPending) === 0;
  }, baselineCycle, { timeout: 120000 });

  const pendingWhileTraceEnabled = await page.evaluate(() => Number(window.__RHDL_UX_STATE__?.uiCyclesPending || 0));
  assert.ok(
    pendingWhileTraceEnabled >= 0 && pendingWhileTraceEnabled < 10,
    `expected pending cycles to stay bounded with trace enabled, got ${pendingWhileTraceEnabled}`
  );

  await page.click('#pauseBtn');
  await page.waitForFunction(() => {
    const ux = window.__RHDL_UX_STATE__;
    return !!ux && ux.running === false;
  }, null, { timeout: 120000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
