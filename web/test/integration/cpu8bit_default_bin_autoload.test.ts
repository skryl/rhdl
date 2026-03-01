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

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });
}

test('8bit cpu runner auto-loads default bin and logs it', { timeout: 180000 }, async (t) => {
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
  await loadCpuRunner(page);

  const selectedBackend = await page.$eval('#backendSelect', (el) => (el as HTMLSelectElement).value);
  assert.equal(selectedBackend, 'compiler');

  await page.waitForFunction(() => {
    const stepTicks = (document.querySelector('#stepTicks') as HTMLInputElement | null)?.value || '';
    const runBatch = (document.querySelector('#runBatch') as HTMLInputElement | null)?.value || '';
    const uiUpdateCycles = (document.querySelector('#uiUpdateCycles') as HTMLInputElement | null)?.value || '';
    return stepTicks === '100' && runBatch === '2000' && uiUpdateCycles === '2000';
  }, null, { timeout: 30000 });

  const perfDefaults = await page.evaluate(() => ({
    stepTicks: (document.querySelector('#stepTicks') as HTMLInputElement | null)?.value || '',
    runBatch: (document.querySelector('#runBatch') as HTMLInputElement | null)?.value || '',
    uiUpdateCycles: (document.querySelector('#uiUpdateCycles') as HTMLInputElement | null)?.value || ''
  }));
  assert.equal(perfDefaults.stepTicks, '100');
  assert.equal(perfDefaults.runBatch, '2000');
  assert.equal(perfDefaults.uiUpdateCycles, '2000');

  await page.waitForFunction(() => {
    const logText = document.querySelector('#eventLog')?.textContent || '';
    return (
      (logText.includes('Loaded default bin (main)') && logText.includes('conway_glider_80x24.bin'))
      || logText.includes('Default bin load skipped (404): ./assets/fixtures/cpu/software/conway_glider_80x24.bin')
    );
  }, null, { timeout: 30000 });

  const eventLog = await page.$eval('#eventLog', (el) => el.textContent || '');
  const defaultBinLoaded = /Loaded default bin \(main\).*conway_glider_80x24\.bin/.test(eventLog);

  await page.fill('#stepTicks', '12000');
  if (defaultBinLoaded) {
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
  } else {
    const startCycle = await page.$eval('#simStatus', (el) => {
      const text = String(el.textContent || '');
      const match = text.match(/Cycle\s+(\d+)/);
      return match ? Number.parseInt(match[1], 10) : 0;
    });
    await page.click('#stepBtn');
    await page.waitForFunction((baseline) => {
      const text = document.querySelector('#simStatus')?.textContent || '';
      const match = text.match(/Cycle\s+(\d+)/);
      return !!match && Number.parseInt(match[1], 10) > Number(baseline);
    }, startCycle, { timeout: 120000 });
  }

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
