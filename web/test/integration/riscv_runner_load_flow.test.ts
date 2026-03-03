import test from 'node:test';
import assert from 'node:assert/strict';
import type { ConsoleMessage, Page } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

function setupTestPage(page: Page) {
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];
  const benignPageErrors = [
    'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
  ];

  page.on('pageerror', (err: Error) => {
    const message = String(err?.message || err);
    if (benignPageErrors.some((entry) => message.includes(entry))) {
      return;
    }
    pageErrors.push(message);
  });

  page.on('console', (msg: ConsoleMessage) => {
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

async function loadRunner(page: Page, runnerId: string): Promise<void> {
  await page.waitForFunction((id: string) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === id);
  }, runnerId, { timeout: 120000, polling: 100 });

  await page.selectOption('#runnerSelect', runnerId);
  await page.click('#loadRunnerBtn');

  await page.waitForFunction((id: string) => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    const normalized = String(text).toLowerCase();
    const normalizedId = String(id).toLowerCase();
    return normalized.includes(normalizedId) || normalized.includes('risc-v');
  }, runnerId, { timeout: 120000, polling: 100 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000, polling: 100 });
}

function getEventLog(page: Page): Promise<string> {
  return page.$eval('#eventLog', (el) => el.textContent || '');
}

function getMemoryDumpPreText(page: Page): Promise<string> {
  return page.$eval('#memoryDump', (el) => {
    const pre = el.shadowRoot?.querySelector('#memoryDumpPre');
    return pre?.textContent || '';
  });
}

function getDisplayText(page: Page): Promise<string> {
  return page.$eval('#apple2TextScreen', (el) => el.textContent || '');
}

function getSimCycle(page: Page): Promise<number> {
  return page.$eval('#simStatus', (el) => {
    const text = String(el.textContent || '');
    const match = text.match(/Cycle\s+(\d+)/);
    return match ? Number.parseInt(match[1], 10) : -1;
  });
}

test('riscv runner loads default kernel, memory, uart and simulation', { timeout: 220000 }, async (t) => {
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
  const { pageErrors, consoleErrors } = setupTestPage(page);

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  await page.selectOption('#backendSelect', 'interpreter');
  await page.dispatchEvent('#backendSelect', 'change');

  await loadRunner(page, 'riscv');

  await page.waitForFunction(() => {
    const log = document.querySelector('#eventLog')?.textContent || '';
    return (
      (log.includes('Loaded default bin (main)') && log.includes('./assets/fixtures/riscv/software/bin/xv6_kernel.bin'))
      || log.includes('Default bin load skipped (404): ./assets/fixtures/riscv/software/bin/xv6_kernel.bin')
    );
  }, null, { timeout: 30000, polling: 100 });

  const eventLog = await getEventLog(page);
  const kernelLoaded = /Loaded default bin \(main\).*xv6_kernel\.bin/.test(eventLog);
  const kernelSkipped = /Default bin load skipped \(404\): .*xv6_kernel\.bin/.test(eventLog);
  assert.ok(kernelLoaded || kernelSkipped, 'expected kernel default bin to load or be explicitly skipped');
  assert.equal(
    eventLog.includes('Default bin load failed or unsupported for space "main"'),
    false,
    'default bin load should be handled via runner memory API'
  );

  await page.click('[data-tab="memoryTab"]');
  await page.fill('#memoryStart', '0x80000000');
  await page.fill('#memoryLength', '32');
  await page.click('#memoryRefreshBtn');

  if (kernelLoaded) {
    await page.waitForFunction(() => {
      const pre = document.querySelector('#memoryDump')?.shadowRoot?.querySelector('#memoryDumpPre');
      const text = pre?.textContent || '';
      return text.includes('17 B1 00 00 13 01 01 40');
    }, null, { timeout: 30000, polling: 100 });
  } else {
    await page.waitForFunction(() => {
      const pre = document.querySelector('#memoryDump')?.shadowRoot?.querySelector('#memoryDumpPre');
      const text = pre?.textContent || '';
      return text.includes('80000000');
    }, null, { timeout: 30000, polling: 100 });
  }

  const memoryDumpText = await getMemoryDumpPreText(page);
  if (kernelLoaded) {
    assert.match(memoryDumpText, /17 B1 00 00 13 01 01 40/);
  }
  assert.match(memoryDumpText, /80000000/);

  await page.click('[data-tab="ioTab"]');
  await page.waitForFunction(() => {
    const text = document.querySelector('#apple2TextScreen')?.textContent || '';
    return text.includes('UART') || text.includes('No UART output yet.');
  }, null, { timeout: 12000, polling: 100 });

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
  }, before, { timeout: 120000, polling: 100 });

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
