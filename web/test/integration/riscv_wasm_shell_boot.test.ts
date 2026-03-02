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

async function waitForRunnerOption(page: Page, runnerId: string) {
  await page.waitForFunction((id: string) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === id);
  }, runnerId, { timeout: 120000 });
}

async function loadRiscvRunnerOnCompiler(page: Page) {
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

function hasShellPrompt(text: string): boolean {
  return /\$\s/.test(text);
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

async function stepUntilShellPrompt(page: Page, { stepTicks = 3_000_000, maxSteps = 20 }: StepOptions = {}): Promise<string> {
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
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && bun install`)');
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

  await loadRiscvRunnerOnCompiler(page);
  const uartText = await stepUntilShellPrompt(page, { stepTicks: 3_000_000, maxSteps: 20 });

  assert.match(uartText, /init: starting sh/);
  assert.equal(hasShellPrompt(uartText), true, 'expected shell prompt in UART output');

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
