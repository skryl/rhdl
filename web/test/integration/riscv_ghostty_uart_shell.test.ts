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

function setupTestPage(page) {
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

async function waitForRunnerOption(page, runnerId) {
  await page.waitForFunction((id) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === id);
  }, runnerId, { timeout: 120000 });
}

async function loadRiscvRunnerOnCompiler(page) {
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

async function ensureTerminalOpen(page) {
  await page.waitForSelector('#terminalPanel', { state: 'attached', timeout: 20000 });
  await page.waitForSelector('#terminalToggleBtn', { state: 'attached', timeout: 20000 });
  const hidden = await page.$eval('#terminalPanel', (panel) => !!panel.hidden);
  if (hidden) {
    await page.click('#terminalToggleBtn');
  }
  await page.waitForFunction(() => {
    const panel = document.querySelector('#terminalPanel');
    return !!panel && panel.hidden === false;
  }, null, { timeout: 20000 });
}

function readTerminalOutput(page) {
  return page.$eval('#terminalOutput', (el) => String(el.dataset?.terminalText ?? el.value ?? el.textContent ?? ''));
}

function getDisplayText(page) {
  return page.$eval('#apple2TextScreen', (el) => el?.textContent || '');
}

function getSimCycle(page) {
  return page.$eval('#simStatus', (el) => {
    const text = String(el?.textContent || '');
    const match = text.match(/Cycle\s+([\d,]+)/);
    return match ? Number.parseInt(match[1].replace(/,/g, ''), 10) : -1;
  });
}

function countOccurrences(haystack, needle) {
  if (!needle) {
    return 0;
  }
  return String(haystack || '').split(needle).length - 1;
}

async function stepUntilDisplayMatch(page, predicate, { stepTicks = 3_000_000, maxSteps = 20 } = {}) {
  await page.click('[data-tab="ioTab"]');

  let lastDisplay = '';
  for (let i = 0; i < maxSteps; i += 1) {
    await page.fill('#stepTicks', String(stepTicks));

    const before = await getSimCycle(page);
    await page.click('#stepBtn');

    await page.waitForFunction((startCycle) => {
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

  await loadRiscvRunnerOnCompiler(page);

  await stepUntilDisplayMatch(
    page,
    (displayText) => displayText.includes('init: starting sh') && /\$\s/.test(displayText),
    { stepTicks: 3_000_000, maxSteps: 20 }
  );

  await ensureTerminalOpen(page);
  await page.waitForFunction(() => {
    const el = document.querySelector('#terminalOutput');
    return (el?.dataset?.terminalRenderer || '') === 'ghostty-web';
  }, null, { timeout: 45000 });

  await page.click('#terminalOutput');
  await page.keyboard.type('terminal uart on');
  await page.keyboard.press('Enter');
  await page.waitForFunction(() => {
    const terminal = window.__RHDL_UX_STATE__?.terminal;
    return !!terminal && terminal.uartPassthrough === true;
  }, null, { timeout: 60000 });

  await page.click('#terminalOutput');
  await page.keyboard.type('echo ghostty_uart_ok');
  await page.keyboard.press('Enter');

  const uartText = await stepUntilDisplayMatch(
    page,
    (displayText) => countOccurrences(displayText, 'ghostty_uart_ok') >= 2,
    { stepTicks: 750_000, maxSteps: 40 }
  );

  assert.equal(countOccurrences(uartText, 'ghostty_uart_ok') >= 2, true, 'expected command echo and output in UART text');
  assert.match(uartText, /init: starting sh/);

  const terminalText = await readTerminalOutput(page);
  const terminalState = await page.evaluate(() => window.__RHDL_UX_STATE__?.terminal || null);
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
