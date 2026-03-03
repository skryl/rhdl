import test from 'node:test';
import assert from 'node:assert/strict';
import type { ConsoleMessage, Page } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

type BackendRunnerCase = {
  backendId: 'arcilator' | 'verilator';
  backendLabel: string;
  runnerId: string;
  runnerLabel: string;
  stepTicks: number;
};

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

const CASES: BackendRunnerCase[] = [
  {
    backendId: 'arcilator',
    backendLabel: 'Arcilator (CIRCT)',
    runnerId: 'apple2',
    runnerLabel: 'Apple II System Runner',
    stepTicks: 2048
  },
  {
    backendId: 'verilator',
    backendLabel: 'Verilator',
    runnerId: 'apple2',
    runnerLabel: 'Apple II System Runner',
    stepTicks: 2048
  },
  {
    backendId: 'arcilator',
    backendLabel: 'Arcilator (CIRCT)',
    runnerId: 'riscv',
    runnerLabel: 'RISC-V xv6 Runner',
    stepTicks: 4096
  },
  {
    backendId: 'verilator',
    backendLabel: 'Verilator',
    runnerId: 'riscv',
    runnerLabel: 'RISC-V xv6 Runner',
    stepTicks: 4096
  }
];

function setupTestPage(page: Page) {
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];

  page.on('pageerror', (err: Error) => {
    const message = String(err?.message || err);
    if (BENIGN_PAGE_ERRORS.some((entry) => message.includes(entry))) {
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

async function waitForSelectOption(page: Page, selector: string, value: string): Promise<void> {
  await page.waitForFunction(({ selectSelector, optionValue }) => {
    const select = document.querySelector(selectSelector);
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === optionValue);
  }, { selectSelector: selector, optionValue: value }, { timeout: 120000, polling: 100 });
}

async function getSimCycle(page: Page): Promise<number> {
  return page.$eval('#simStatus', (el) => {
    const text = String(el.textContent || '');
    const match = text.match(/Cycle\s+([\d,]+)/);
    return match ? Number.parseInt(match[1].replace(/,/g, ''), 10) : -1;
  });
}

async function runBackendCase(page: Page, scenario: BackendRunnerCase): Promise<void> {
  await waitForSelectOption(page, '#backendSelect', scenario.backendId);
  await page.selectOption('#backendSelect', scenario.backendId);
  await page.dispatchEvent('#backendSelect', 'change');

  await waitForSelectOption(page, '#runnerSelect', scenario.runnerId);
  await page.selectOption('#runnerSelect', scenario.runnerId);
  await page.click('#loadRunnerBtn');

  await page.waitForFunction(({ runnerLabel, backendLabel }) => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes(runnerLabel) && text.includes(backendLabel);
  }, { runnerLabel: scenario.runnerLabel, backendLabel: scenario.backendLabel }, { timeout: 120000, polling: 100 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000, polling: 100 });

  const startCycle = await getSimCycle(page);
  await page.fill('#stepTicks', String(scenario.stepTicks));
  await page.click('#stepBtn');

  await page.waitForFunction((previousCycle) => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    const match = text.match(/Cycle\s+([\d,]+)/);
    if (!match) {
      return false;
    }
    const cycle = Number.parseInt(match[1].replace(/,/g, ''), 10);
    return Number.isFinite(cycle) && cycle > Number(previousCycle);
  }, startCycle, { timeout: 120000, polling: 100 });

  const simStatus = await page.$eval('#simStatus', (el) => String(el.textContent || ''));
  assert.equal(
    simStatus.includes(`Backend ${scenario.backendId} unavailable:`),
    false,
    `expected backend ${scenario.backendId} to stay available for ${scenario.runnerId}`
  );

  const eventLog = await page.$eval('#eventLog', (el) => String(el.textContent || ''));
  assert.equal(
    eventLog.includes(`Backend load failed (${scenario.backendId})`),
    false,
    `expected no backend load failure for ${scenario.backendId} on ${scenario.runnerId}`
  );
  assert.equal(
    eventLog.includes('Failed to load runner'),
    false,
    `expected runner load success for ${scenario.backendId} on ${scenario.runnerId}`
  );
  assert.equal(
    eventLog.includes('Initialization failed:'),
    false,
    `expected simulator initialization success for ${scenario.backendId} on ${scenario.runnerId}`
  );

  if (scenario.backendId === 'verilator') {
    await page.click('[data-tab="componentGraphTab"]');
    await page.waitForFunction(() => {
      const panel = document.querySelector('#componentGraphTab');
      return !!panel && panel.classList.contains('active');
    }, null, { timeout: 120000, polling: 100 });
    await page.waitForSelector('#componentVisual canvas', { state: 'attached', timeout: 120000 });
    const visualText = await page.$eval('#componentVisual', (el) => String(el.textContent || ''));
    assert.equal(
      visualText.includes('Unable to render component schematic.'),
      false,
      `expected schematic canvas to render for ${scenario.backendId} on ${scenario.runnerId}`
    );
  }
}

test('arcilator and verilator backends load and run for apple2 + riscv', { timeout: 520000 }, async (t) => {
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
  const baseUrl = serverBaseUrl(server);

  for (const scenario of CASES) {
    await page.goto(`${baseUrl}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 20000 });
    await runBackendCase(page, scenario);
  }

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
