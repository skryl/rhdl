import test from 'node:test';
import assert from 'node:assert/strict';
import type { Page } from 'playwright';

import {
  createStaticServer,
  resolveWebRoot,
  serverBaseUrl
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

type UxState = {
  cycle?: number;
};

type WindowWithUxState = Window & {
  __RHDL_UX_STATE__?: UxState;
};

async function loadApple2Runner(page: Page) {
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
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && npm install`)');
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
    console.warn('Playwright browser binaries are missing (run: `cd web && npx playwright install chromium`)');
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
    if (msg.type() !== 'error') {
      return;
    }
    const text = msg.text();
    if (text.includes('Failed to load resource: the server responded with a status of 404')) {
      return;
    }
    consoleErrors.push(text);
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });
  await loadApple2Runner(page);

  await page.waitForFunction(() => {
    const text = document.querySelector('#traceStatus')?.textContent || '';
    return text.includes('Trace disabled');
  }, null, { timeout: 120000 });

  const baselineCycle = await page.evaluate(() => {
    const ux = (window as WindowWithUxState).__RHDL_UX_STATE__;
    return Number(ux?.cycle || 0);
  });
  for (let i = 0; i < 8; i += 1) {
    await page.click('#stepBtn');
  }
  await page.waitForFunction((baseline) => {
    const ux = (window as WindowWithUxState).__RHDL_UX_STATE__;
    return Number(ux?.cycle || 0) > Number(baseline);
  }, baselineCycle, { timeout: 120000 });

  await page.click('#traceStartBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#traceStatus')?.textContent || '';
    return text.includes('Trace enabled');
  }, null, { timeout: 120000 });

  const traceBaselineCycle = await page.evaluate(() => {
    const ux = (window as WindowWithUxState).__RHDL_UX_STATE__;
    return Number(ux?.cycle || 0);
  });
  for (let i = 0; i < 8; i += 1) {
    await page.click('#stepBtn');
  }
  await page.waitForFunction((baseline) => {
    const ux = (window as WindowWithUxState).__RHDL_UX_STATE__;
    return Number(ux?.cycle || 0) > Number(baseline);
  }, traceBaselineCycle, { timeout: 120000 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#traceStatus')?.textContent || '';
    const match = text.match(/changes\s+(\d+)/i);
    return text.includes('Trace enabled') && (!!match ? Number.parseInt(match[1], 10) > 0 : true);
  }, null, { timeout: 120000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
