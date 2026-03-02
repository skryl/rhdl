import test from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import type { ConsoleMessage, Page } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

type TerminalTextElement = Element & {
  dataset?: DOMStringMap;
  value?: string;
};

type TerminalUxState = {
  uartPassthrough?: boolean;
  history?: string[];
};

type UxState = {
  terminal?: TerminalUxState;
};

type WindowWithUxState = Window & {
  __RHDL_UX_STATE__?: UxState;
};

type StepOptions = {
  stepTicks?: number;
  maxSteps?: number;
};

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

async function waitForRunnerOption(page: Page, runnerId: string): Promise<void> {
  await page.waitForFunction((id: string) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === id);
  }, runnerId, { timeout: 120000 });
}

async function loadRiscvRunnerOnCompiler(page: Page): Promise<void> {
  await waitForRunnerOption(page, 'riscv');

  await page.selectOption('#backendSelect', 'compiler');
  await page.dispatchEvent('#backendSelect', 'change');

  await page.selectOption('#runnerSelect', 'riscv');
  await page.click('#loadRunnerBtn');

  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('RISC-V xv6 Runner') && text.includes('Compiler');
  }, null, { timeout: 120000 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });

  await page.waitForFunction(() => {
    const log = document.querySelector('#eventLog')?.textContent || '';
    const hasFastBootPatch = /Applied RISC-V (aggressive|moderate) fast-boot PHYSTOP patch/.test(log);
    return log.includes('Loaded default bin (main)')
      && log.includes('./assets/fixtures/riscv/software/bin/kernel.bin')
      && log.includes('./assets/fixtures/riscv/software/bin/fs.img')
      && hasFastBootPatch;
  }, null, { timeout: 120000 });
}

async function ensureTerminalOpen(page: Page): Promise<void> {
  await page.waitForSelector('#terminalPanel', { state: 'attached', timeout: 20000 });
  await page.waitForSelector('#terminalToggleBtn', { state: 'attached', timeout: 20000 });
  const hidden = await page.$eval('#terminalPanel', (panel) => (panel as HTMLElement).hidden);
  if (hidden) {
    await page.click('#terminalToggleBtn');
  }
  await page.waitForFunction(() => {
    const panel = document.querySelector('#terminalPanel');
    return panel instanceof HTMLElement && panel.hidden === false;
  }, null, { timeout: 20000 });
}

function readTerminalOutput(page: Page): Promise<string> {
  return page.$eval('#terminalOutput', (el) => {
    const terminalEl = el as TerminalTextElement;
    return String(terminalEl.dataset?.terminalText ?? terminalEl.value ?? terminalEl.textContent ?? '');
  });
}

function getDisplayText(page: Page): Promise<string> {
  return page.$eval('#apple2TextScreen', (el) => el.textContent || '');
}

function getSimCycle(page: Page): Promise<number> {
  return page.$eval('#simStatus', (el) => {
    const text = String(el.textContent || '');
    const match = text.match(/Cycle\s+([\d,]+)/);
    return match ? Number.parseInt(match[1].replace(/,/g, ''), 10) : -1;
  });
}

function countOccurrences(haystack: string, needle: string): number {
  if (!needle) {
    return 0;
  }
  return haystack.split(needle).length - 1;
}

async function hasRiscvShellAssets(webRoot: string): Promise<boolean> {
  const required = [
    path.join(webRoot, 'assets', 'fixtures', 'riscv', 'software', 'bin', 'kernel.bin'),
    path.join(webRoot, 'assets', 'fixtures', 'riscv', 'software', 'bin', 'fs.img')
  ];
  try {
    await Promise.all(required.map(async (filePath) => access(filePath)));
    return true;
  } catch (_err: unknown) {
    return false;
  }
}

async function stepUntilDisplayMatch(
  page: Page,
  predicate: (displayText: string) => boolean,
  { stepTicks = 3_000_000, maxSteps = 20 }: StepOptions = {}
): Promise<string> {
  await page.click('[data-tab="ioTab"]');

  let lastDisplay = '';
  for (let i = 0; i < maxSteps; i += 1) {
    await page.fill('#stepTicks', String(stepTicks));

    const before = await getSimCycle(page);
    await page.click('#stepBtn');

    await page.waitForFunction((startCycle: number) => {
      const text = document.querySelector('#simStatus')?.textContent || '';
      const match = text.match(/Cycle\s+([\d,]+)/);
      if (!match) {
        return false;
      }
      const nextCycle = Number.parseInt(match[1].replace(/,/g, ''), 10);
      return Number.isFinite(nextCycle) && nextCycle > startCycle;
    }, before, { timeout: 120000 });

    const displayText = await getDisplayText(page);
    lastDisplay = displayText;
    if (predicate(displayText)) {
      return displayText;
    }
  }

  throw new Error(`Timed out waiting for UART condition. Last UART text:\n${lastDisplay}`);
}

test('ghostty keyboard can interact with riscv uart shell', { timeout: 320000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && npm install`)');
    return;
  }

  const webRoot = resolveWebRoot(import.meta.url);
  if (!(await hasRiscvShellAssets(webRoot))) {
    console.warn('riscv shell assets are missing (run: `bundle exec rake web:build`)');
    return;
  }
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
  const { pageErrors, consoleErrors } = setupTestPage(page);

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  await loadRiscvRunnerOnCompiler(page);

  await stepUntilDisplayMatch(
    page,
    (displayText: string) => displayText.includes('init: starting sh') && /\$\s/.test(displayText),
    { stepTicks: 3_000_000, maxSteps: 20 }
  );

  await ensureTerminalOpen(page);
  await page.waitForFunction(() => {
    const terminalEl = document.querySelector('#terminalOutput') as TerminalTextElement | null;
    return (terminalEl?.dataset?.terminalRenderer || '') === 'ghostty-web';
  }, null, { timeout: 45000 });

  await page.click('#terminalOutput');
  await page.keyboard.type('terminal uart on');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => {
    const terminal = (window as WindowWithUxState).__RHDL_UX_STATE__?.terminal;
    return !!terminal && terminal.uartPassthrough === true;
  }, null, { timeout: 60000 });

  await page.click('#terminalOutput');
  await page.keyboard.type('echo ghostty_uart_ok');
  await page.keyboard.press('Enter');

  const uartText = await stepUntilDisplayMatch(
    page,
    (displayText: string) => countOccurrences(displayText, 'ghostty_uart_ok') >= 2,
    { stepTicks: 750_000, maxSteps: 40 }
  );

  assert.equal(countOccurrences(uartText, 'ghostty_uart_ok') >= 2, true, 'expected command echo and output in UART text');
  assert.match(uartText, /init: starting sh/);

  const terminalText = await readTerminalOutput(page);
  const terminalState = await page.evaluate(() => (window as WindowWithUxState).__RHDL_UX_STATE__?.terminal || null);
  assert.equal(
    Array.isArray(terminalState?.history) ? terminalState.history.includes('echo ghostty_uart_ok') : false,
    false,
    'expected Ghostty keystrokes to bypass terminal command history while UART passthrough is enabled'
  );
  const bootIndex = terminalText.indexOf('xv6 kernel is booting');
  const initIndex = terminalText.indexOf('init: starting sh');
  assert.equal(bootIndex >= 0 && initIndex > bootIndex, true, 'expected boot and init text in Ghostty UART view');
  assert.match(
    terminalText.slice(bootIndex, initIndex),
    /\n/,
    'expected UART newline rendering between boot and init lines'
  );

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
