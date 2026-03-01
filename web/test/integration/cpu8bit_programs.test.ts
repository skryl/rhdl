import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import type { Page } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

async function switchInterpreterBackend(page: Page) {
  await page.selectOption('#backendSelect', 'interpreter');
  await page.dispatchEvent('#backendSelect', 'change');
  await page.waitForFunction(() => {
    const backend = (document.querySelector('#backendSelect') as HTMLSelectElement)?.value || '';
    const runner = document.querySelector('#runnerStatus')?.textContent || '';
    const sim = document.querySelector('#simStatus')?.textContent || '';
    return backend === 'interpreter'
      && runner.includes('CPU (examples/8bit/hdl/cpu)')
      && runner.includes('Interpreter')
      && sim.includes('Cycle 0');
  }, null, { timeout: 120000 });
}

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

test('8bit cpu runner loads software binaries and renders expected screen output', { timeout: 180000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && npm install`)');
    return;
  }

  const webRoot = resolveWebRoot(import.meta.url);
  const repoRoot = path.resolve(webRoot, '..');
  const programsPath = path.join(repoRoot, 'examples', '8bit', 'software', 'programs.json');
  const programsConfig = JSON.parse(await readFile(programsPath, 'utf8'));
  const programs = Array.isArray(programsConfig.programs) ? programsConfig.programs : [];
  assert.ok(programs.length > 0, 'expected 8bit software programs');

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
    if (msg.type() === 'error') {
      consoleErrors.push(msg.text());
    }
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  for (const program of programs) {
    const programPath = path.join(repoRoot, String(program.binPath || ''));
    const expectCfg = program.expect || {};
    const expectedRow = Number.parseInt(expectCfg.row, 10);
    const expectedCol = Number.parseInt(expectCfg.col, 10);
    const expectedChar = String(expectCfg.char || '');

    assert.ok(Number.isFinite(expectedRow), `invalid expected row for ${program.id}`);
    assert.ok(Number.isFinite(expectedCol), `invalid expected col for ${program.id}`);
    assert.equal(expectedChar.length, 1, `invalid expected char for ${program.id}`);

    await loadCpuRunner(page);
    await switchInterpreterBackend(page);
    await page.click('[data-tab="memoryTab"]');
    await page.setInputFiles('#memoryDumpFile', programPath);
    await page.fill('#memoryDumpOffset', '0x0000');
    await page.click('#memoryDumpLoadBtn');

    await page.waitForFunction((name) => {
      const text = document.querySelector('#memoryDumpStatus')?.textContent || '';
      return text.includes(`Loaded ${name}`);
    }, path.basename(programPath), { timeout: 30000 });

    await page.click('#resetBtn');
    await page.waitForFunction(() => {
      const text = document.querySelector('#simStatus')?.textContent || '';
      return text.includes('Cycle 0');
    }, null, { timeout: 30000 });

    await page.fill('#stepTicks', '4000');
    await page.click('#stepBtn');

    await page.waitForFunction(({ row, col, ch }) => {
      const screenText = document.querySelector('#apple2TextScreen')?.textContent || '';
      const lines = screenText.split('\n');
      if (lines.length <= row) {
        return false;
      }
      const line = lines[row] || '';
      return line[col] === ch;
    }, { row: expectedRow, col: expectedCol, ch: expectedChar }, { timeout: 30000 });

    const observedChar = await page.evaluate(({ row, col }) => {
      const screenText = document.querySelector('#apple2TextScreen')?.textContent || '';
      const lines = screenText.split('\n');
      return (lines[row] || '')[col] || '';
    }, { row: expectedRow, col: expectedCol });

    assert.equal(
      observedChar,
      expectedChar,
      `screen mismatch for ${program.id} at row=${expectedRow} col=${expectedCol}`
    );
  }

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
