import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Browser, ConsoleMessage, Page, Route } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

// Minimal source map covering a few instructions at 0x80000000.
const MOCK_SRCMAP = {
  format: 'rhdl.riscv.srcmap.v1',
  files: ['kernel/start.c', 'kernel/main.c'],
  functions: [
    [0x80000000, 0x40, '_entry', 0],
    [0x80000040, 0x100, 'main', 1]
  ],
  lines: [
    [0x80000000, 0, 5],
    [0x80000004, 0, 6],
    [0x80000008, 0, 7],
    [0x80000040, 1, 10],
    [0x80000044, 1, 11]
  ],
  sources: {
    'kernel/start.c': 'line1\nline2\nline3\nline4\nvoid _entry(void) {\n  setup_stack();\n  jump_to_main();\n}\n',
    'kernel/main.c': 'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nvoid main(void) {\n  kinit();\n}\n'
  }
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
    if (text.includes('service worker')) {
      return;
    }
    consoleErrors.push(text);
  });

  return { pageErrors, consoleErrors };
}

// Route CDN requests to locally bundled copies.
async function routeCdnToLocal(page: Page): Promise<void> {
  const webRoot = resolveWebRoot(import.meta.url);
  const nodeModules = path.resolve(webRoot, 'node_modules');
  const cacheDir = path.join(nodeModules, '.cache');

  await page.route('**/cdn.jsdelivr.net/npm/lit@*/+esm', async (route: Route) => {
    try {
      const body = await readFile(path.join(cacheDir, 'lit-bundle.mjs'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err: unknown) {
      await route.abort();
    }
  });

  await page.route('**/cdn.jsdelivr.net/npm/lit-html@*/+esm', async (route: Route) => {
    try {
      const body = await readFile(path.join(cacheDir, 'lit-html-bundle.mjs'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err: unknown) {
      await route.abort();
    }
  });

  await page.route('**/cdn.jsdelivr.net/npm/redux@*/dist/redux.min.js', async (route: Route) => {
    try {
      const body = await readFile(path.join(nodeModules, 'redux', 'dist', 'redux.min.js'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err: unknown) {
      await route.abort();
    }
  });

  await page.route('**/cdn.jsdelivr.net/npm/p5@*/lib/p5.min.js', async (route: Route) => {
    await route.fulfill({
      body: 'window.p5 = class p5 { constructor() {} };',
      contentType: 'text/javascript; charset=utf-8'
    });
  });

  await page.route('**/cdn.jsdelivr.net/npm/cytoscape@*/dist/cytoscape.min.js', async (route: Route) => {
    await route.fulfill({
      body: 'window.cytoscape = function() { return { on() {}, destroy() {} }; };',
      contentType: 'text/javascript; charset=utf-8'
    });
  });

  await page.route('**/cdn.jsdelivr.net/npm/elkjs@*/lib/elk.bundled.js', async (route: Route) => {
    await route.fulfill({
      body: 'window.ELK = class ELK { layout() { return Promise.resolve({}); } };',
      contentType: 'text/javascript; charset=utf-8'
    });
  });

  await page.route('**/coi-serviceworker.js', async (route: Route) => {
    await route.fulfill({
      body: '/* stub */',
      contentType: 'text/javascript; charset=utf-8'
    });
  });

  await page.route('**/fonts.googleapis.com/**', (route: Route) => route.fulfill({
    body: '',
    contentType: 'text/css'
  }));
  await page.route('**/fonts.gstatic.com/**', (route: Route) => route.fulfill({
    body: '',
    contentType: 'font/woff2'
  }));
}

async function loadRiscvRunner(page: Page): Promise<void> {
  await page.waitForFunction(() => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    return Array.from(select.options).some((opt) => opt.value === 'riscv');
  }, null, { timeout: 120000 });

  await page.selectOption('#backendSelect', 'interpreter');
  await page.dispatchEvent('#backendSelect', 'change');

  await page.selectOption('#runnerSelect', 'riscv');
  await page.click('#loadRunnerBtn');

  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('RISC-V') || text.includes('riscv');
  }, null, { timeout: 120000 });

  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0') && text.includes('PAUSED');
  }, null, { timeout: 120000 });
}

function getDisasmPreText(page: Page): Promise<string> {
  return page.$eval('#memoryDump', (el) => {
    const pre = el.shadowRoot?.querySelector('#memoryDisasmPre');
    return pre?.textContent || '';
  });
}

function getShowSourceChecked(page: Page): Promise<boolean> {
  return page.$eval('#memoryShowSource', (el) => (el as HTMLInputElement).checked);
}

function getShowSourceDisabled(page: Page): Promise<boolean> {
  return page.$eval('#memoryShowSource', (el) => (el as HTMLInputElement).disabled);
}

async function navigateToMemoryAndRefresh(page: Page): Promise<void> {
  await page.click('[data-tab="memoryTab"]');
  await page.fill('#memoryStart', '0x80000000');
  await page.fill('#memoryLength', '256');
  await page.click('#memoryRefreshBtn');

  await page.waitForFunction(() => {
    const el = document.querySelector('#memoryDump');
    const pre = el?.shadowRoot?.querySelector('#memoryDisasmPre');
    const text = pre?.textContent || '';
    return text.includes('80000000') && text.length > 40;
  }, null, { timeout: 60000 });
}

// -----------------------------------------------------------------------
// All three RISC-V disassembly/source-map scenarios share a single browser
// to avoid resource contention between sequential browser launches.
// -----------------------------------------------------------------------
test('riscv disassembly and source map integration', { timeout: 300000, concurrency: false }, async (t) => {
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

  let browser: Browser | null = null;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (_err: unknown) {
    console.warn('Playwright browser binaries are missing (run: `cd web && bunx playwright install chromium`)');
    return;
  }
  t.after(async () => {
    if (browser) {
      await browser.close();
    }
  });

  async function withScenarioPage(run: (page: Page, pageErrors: string[]) => Promise<void>) {
    if (!browser) {
      throw new Error('browser is not initialized');
    }
    const context = await browser.newContext();
    const page = await context.newPage();
    const { pageErrors } = setupTestPage(page);

    try {
      await run(page, pageErrors);
    } finally {
      await context.close();
    }
  }

  // Scenario 1: RISC-V disassembly renders in memory panel.
  await withScenarioPage(async (page, pageErrors) => {
    await routeCdnToLocal(page);

    await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });

    await loadRiscvRunner(page);
    await navigateToMemoryAndRefresh(page);

    const disasmText = await getDisasmPreText(page);

    assert.match(disasmText, /80000000/);
    assert.match(disasmText, /auipc|addi|lui|jal|li|mv|c\.\w+|unimp/i,
      'expected RISC-V mnemonics in disassembly output');
    assert.ok(disasmText.split('\n').length > 5, 'expected multiple disassembly lines');

    assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  });

  // Scenario 2: C Source toggle shows source annotations.
  await withScenarioPage(async (page, pageErrors) => {
    await routeCdnToLocal(page);

    await page.route('**/kernel_srcmap.json', async (route: Route) => {
      await route.fulfill({
        body: JSON.stringify(MOCK_SRCMAP),
        contentType: 'application/json; charset=utf-8'
      });
    });

    await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });

    await loadRiscvRunner(page);

    await page.waitForFunction(() => {
      const log = document.querySelector('#eventLog')?.textContent || '';
      return log.includes('Loaded source map');
    }, null, { timeout: 30000 });

    await navigateToMemoryAndRefresh(page);

    const disabledBefore = await getShowSourceDisabled(page);
    assert.equal(disabledBefore, false, 'C Source toggle should be enabled when srcmap is loaded');

    await page.check('#memoryShowSource');
    await page.click('#memoryRefreshBtn');

    await page.waitForFunction(() => {
      const el = document.querySelector('#memoryDump');
      const pre = el?.shadowRoot?.querySelector('#memoryDisasmPre');
      const text = pre?.textContent || '';
      return text.includes('_entry') || text.includes('start.c');
    }, null, { timeout: 30000 });

    const disasmWithSource = await getDisasmPreText(page);

    assert.match(disasmWithSource, /-- _entry\(\).*--/,
      'expected function header annotation in disassembly');
    assert.match(disasmWithSource, /5:|6:|7:/,
      'expected source line numbers in disassembly');
    assert.match(disasmWithSource, /80000000/,
      'expected addresses still present with source annotations');

    await page.uncheck('#memoryShowSource');
    await page.click('#memoryRefreshBtn');

    await page.waitForFunction(() => {
      const el = document.querySelector('#memoryDump');
      const pre = el?.shadowRoot?.querySelector('#memoryDisasmPre');
      const text = pre?.textContent || '';
      return text.includes('80000000') && !text.includes('_entry');
    }, null, { timeout: 30000 });

    const disasmWithoutSource = await getDisasmPreText(page);
    assert.equal(disasmWithoutSource.includes('_entry'), false,
      'source annotations should disappear when toggle is off');

    assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  });

  // Scenario 3: C Source toggle is disabled when no source map is loaded.
  await withScenarioPage(async (page, pageErrors) => {
    await routeCdnToLocal(page);

    await page.route('**/kernel_srcmap.json', async (route: Route) => {
      await route.fulfill({
        status: 404,
        body: 'Not found',
        contentType: 'text/plain'
      });
    });

    await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });

    await loadRiscvRunner(page);

    await page.waitForFunction(() => {
      const log = document.querySelector('#eventLog')?.textContent || '';
      return log.includes('Source map load skipped') || log.includes('Loaded default bin');
    }, null, { timeout: 30000 });

    await navigateToMemoryAndRefresh(page);

    const disabled = await getShowSourceDisabled(page);
    assert.equal(disabled, true, 'C Source toggle should be disabled when no srcmap is loaded');

    const checked = await getShowSourceChecked(page);
    assert.equal(checked, false, 'C Source toggle should be unchecked when disabled');

    const disasmText = await getDisasmPreText(page);
    assert.match(disasmText, /80000000/);
    assert.match(disasmText, /auipc|addi|lui|jal|li|mv|c\.\w+|unimp/i,
      'expected RISC-V mnemonics in disassembly');
    assert.equal(disasmText.includes('-- '), false,
      'should not have source annotations without srcmap');

    assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  });
});
