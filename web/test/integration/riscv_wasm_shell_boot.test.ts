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

function setupTestPage(page: any) {
  const pageErrors: any[] = [];
  const consoleErrors: any[] = [];

  page.on('pageerror', (err: any) => {
    const message = String(err?.message || err);
    if (BENIGN_PAGE_ERRORS.some((entry) => message.includes(entry))) {
      return;
    }
    pageErrors.push(message);
  });

  page.on('console', (msg: any) => {
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

async function waitForRunnerOption(page: any, runnerId: any) {
  await page.waitForFunction((id: any) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === id);
  }, runnerId, { timeout: 120000 });
}

async function loadRiscvRunnerOnCompiler(page: any) {
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

function getDisplayText(page: any) {
  return page.$eval('#apple2TextScreen', (el: any) => el?.textContent || '');
}

function getSimCycle(page: any) {
  return page.$eval('#simStatus', (el: any) => {
    const text = String(el?.textContent || '');
    const match = text.match(/Cycle\s+([\d,]+)/);
    return match ? Number.parseInt(match[1].replace(/,/g, ''), 10) : -1;
  });
}

function hasShellPrompt(text: any) {
  return /\$\s/.test(String(text || ''));
}

async function stepUntilShellPrompt(page: any, { stepTicks = 3_000_000, maxSteps = 20 }: any = {}) {
  await page.click('[data-tab="ioTab"]');

  let lastDisplay = '';
  for (let i = 0; i < maxSteps; i += 1) {
    await page.fill('#stepTicks', String(stepTicks));

    const before = await getSimCycle(page);
    await page.click('#stepBtn');

    await page.waitForFunction((startCycle: any) => {
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

    if (displayText.includes('init: starting sh') && hasShellPrompt(displayText)) {
      return displayText;
    }
  }

  throw new Error(`Timed out waiting for xv6 shell prompt. Last UART text:\n${lastDisplay}`);
}

test('riscv wasm compiler boots xv6 to init and shell prompt', { timeout: 260000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err: any) {
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
  } catch (_err: any) {
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
  const uartText = await stepUntilShellPrompt(page, { stepTicks: 3_000_000, maxSteps: 20 });

  assert.match(uartText, /init: starting sh/);
  assert.equal(hasShellPrompt(uartText), true, 'expected shell prompt in UART output');

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
