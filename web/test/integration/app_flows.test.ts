import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];
type TextCarrierElement = Element & {
  dataset?: DOMStringMap;
  value?: string;
};

test('web app core flows run in a real browser session', { timeout: 180000 }, async (t) => {
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
    const dumpStatus = document.querySelector('#memoryDumpStatus')?.textContent || '';
    const eventLog = document.querySelector('#eventLog')?.textContent || '';
    return dumpStatus.includes('Loaded Karateka dump')
      || eventLog.includes('Karateka load failed');
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
    (document.querySelector('#runBtn') as HTMLElement)?.click();
  });
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('RUNNING');
  }, null, { timeout: 120000 });

  await page.evaluate(() => {
    (document.querySelector('#pauseBtn') as HTMLElement)?.click();
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
    const textHost = el as TextCarrierElement | null;
    const text = String(textHost?.dataset?.terminalText ?? textHost?.value ?? textHost?.textContent ?? '');
    return text.includes('runner=apple2') && /backend=\S+/.test(text);
  }, null, { timeout: 120000 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
