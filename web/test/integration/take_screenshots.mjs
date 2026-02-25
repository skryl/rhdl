#!/usr/bin/env node
/**
 * Take documentation screenshots for the web simulator.
 *
 * Usage:
 *   cd web && node test/integration/take_screenshots.mjs
 *
 * Produces PNGs under docs/screenshots/.
 */

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFile, mkdir } from 'node:fs/promises';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DOCS_DIR = path.resolve(__dirname, '..', '..', '..', 'docs', 'screenshots');

const MAIN_VIEWPORT  = { width: 1660, height: 970 };
const RISCV_VIEWPORT = { width: 1280, height: 800 };
const DEVICE_SCALE   = 2;

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

// Route CDN requests to locally bundled copies so screenshots work offline.
async function routeCdnToLocal(page) {
  const webRoot = resolveWebRoot(import.meta.url);
  const nodeModules = path.resolve(webRoot, 'node_modules');
  const cacheDir = path.join(nodeModules, '.cache');

  await page.route('**/cdn.jsdelivr.net/npm/lit@*/+esm', async (route) => {
    try {
      const body = await readFile(path.join(cacheDir, 'lit-bundle.mjs'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err) { await route.abort(); }
  });
  await page.route('**/cdn.jsdelivr.net/npm/lit-html@*/+esm', async (route) => {
    try {
      const body = await readFile(path.join(cacheDir, 'lit-html-bundle.mjs'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err) { await route.abort(); }
  });
  await page.route('**/cdn.jsdelivr.net/npm/redux@*/dist/redux.min.js', async (route) => {
    try {
      const body = await readFile(path.join(nodeModules, 'redux', 'dist', 'redux.min.js'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err) { await route.abort(); }
  });
  await page.route('**/cdn.jsdelivr.net/npm/p5@*/lib/p5.min.js', async (route) => {
    try {
      const body = await readFile(path.join(nodeModules, 'p5', 'lib', 'p5.min.js'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err) {
      await route.fulfill({
        body: 'window.p5 = class p5 { constructor() {} };',
        contentType: 'text/javascript; charset=utf-8'
      });
    }
  });
  await page.route('**/cdn.jsdelivr.net/npm/cytoscape@*/dist/cytoscape.min.js', async (route) => {
    try {
      const body = await readFile(path.join(nodeModules, 'cytoscape', 'dist', 'cytoscape.min.js'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err) {
      await route.fulfill({
        body: 'window.cytoscape = function() { return { on() {}, destroy() {} }; };',
        contentType: 'text/javascript; charset=utf-8'
      });
    }
  });
  await page.route('**/cdn.jsdelivr.net/npm/elkjs@*/lib/elk.bundled.js', async (route) => {
    try {
      const body = await readFile(path.join(nodeModules, 'elkjs', 'lib', 'elk.bundled.js'), 'utf-8');
      await route.fulfill({ body, contentType: 'text/javascript; charset=utf-8' });
    } catch (_err) {
      await route.fulfill({
        body: 'window.ELK = class ELK { layout() { return Promise.resolve({}); } };',
        contentType: 'text/javascript; charset=utf-8'
      });
    }
  });

  await page.route('**/coi-serviceworker.js', async (route) => {
    await route.fulfill({ body: '/* stub */', contentType: 'text/javascript; charset=utf-8' });
  });
  await page.route('**/fonts.googleapis.com/**', (route) => route.fulfill({
    body: '', contentType: 'text/css'
  }));
  await page.route('**/fonts.gstatic.com/**', (route) => route.fulfill({
    body: '', contentType: 'font/woff2'
  }));
}

async function shot(page, name) {
  const dest = path.join(DOCS_DIR, `${name}.png`);
  await page.screenshot({ path: dest, fullPage: false, timeout: 60000 });
  console.log(`  saved ${name}.png`);
}

async function takeMainScreenshots(browser, baseUrl) {
  console.log('\n--- Main tab screenshots ---');

  const context = await browser.newContext({
    viewport: MAIN_VIEWPORT,
    deviceScaleFactor: DEVICE_SCALE
  });
  const page = await context.newPage();
  await routeCdnToLocal(page);

  await page.goto(`${baseUrl}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 30000 });

  // Load Apple II runner
  await page.click('#loadRunnerBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('Apple II System Runner');
  }, null, { timeout: 120000 });
  await page.waitForFunction(() => {
    const text = document.querySelector('#simStatus')?.textContent || '';
    return text.includes('Cycle 0');
  }, null, { timeout: 120000 });

  // Let UI settle
  await page.waitForTimeout(2000);

  // 1. I/O tab (default active)
  await page.click('[data-tab="ioTab"]');
  await page.waitForTimeout(1000);
  await shot(page, 'io');

  // 2. VCD + Signals tab
  await page.click('[data-tab="vcdTab"]');
  await page.waitForTimeout(1000);
  await shot(page, 'signals');

  // 3. Memory tab
  await page.click('[data-tab="memoryTab"]');
  await page.waitForTimeout(1000);
  await shot(page, 'memory');

  // 4. Components tab
  await page.click('[data-tab="componentTab"]');
  await page.waitForTimeout(1000);
  await shot(page, 'explorer');

  // 5. Schematic tab
  await page.click('[data-tab="componentGraphTab"]');
  await page.waitForTimeout(2000); // schematic layout needs extra time
  await shot(page, 'schematic');

  await context.close();
}

async function takeRiscvScreenshots(browser, baseUrl) {
  console.log('\n--- RISC-V disassembly screenshots ---');

  // --- no srcmap ---
  console.log('  scenario: no srcmap');
  {
    const context = await browser.newContext({
      viewport: RISCV_VIEWPORT,
      deviceScaleFactor: DEVICE_SCALE
    });
    const page = await context.newPage();
    await routeCdnToLocal(page);

    // block srcmap so toggle stays disabled
    await page.route('**/kernel_srcmap.json', async (route) => {
      await route.fulfill({ status: 404, body: 'Not found', contentType: 'text/plain' });
    });

    await page.goto(`${baseUrl}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });

    await loadRiscvRunner(page);
    await navigateToMemoryAndRefresh(page);
    await ensureMemoryTabActive(page);
    await shot(page, 'riscv_disasm_no_srcmap');

    await context.close();
  }

  // --- srcmap loaded, toggle off ---
  console.log('  scenario: srcmap loaded, toggle off');
  {
    const context = await browser.newContext({
      viewport: RISCV_VIEWPORT,
      deviceScaleFactor: DEVICE_SCALE
    });
    const page = await context.newPage();
    await routeCdnToLocal(page);

    await page.route('**/kernel_srcmap.json', async (route) => {
      await route.fulfill({
        body: JSON.stringify(MOCK_SRCMAP),
        contentType: 'application/json; charset=utf-8'
      });
    });

    await page.goto(`${baseUrl}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });

    await loadRiscvRunner(page);

    // Wait for srcmap to load
    await page.waitForFunction(() => {
      const log = document.querySelector('#eventLog')?.textContent || '';
      return log.includes('Loaded source map');
    }, null, { timeout: 30000 });

    await navigateToMemoryAndRefresh(page);
    // Ensure toggle is OFF
    const checked = await page.$eval('#memoryShowSource', (el) => !!el?.checked);
    if (checked) {
      await page.evaluate(() => {
        const cb = document.querySelector('#memoryShowSource');
        if (cb) { cb.checked = false; cb.dispatchEvent(new Event('change')); }
        document.querySelector('#memoryRefreshBtn')?.click();
      });
      await page.waitForTimeout(500);
    }
    await ensureMemoryTabActive(page);
    await shot(page, 'riscv_disasm_srcmap_off');

    await context.close();
  }

  // --- srcmap loaded, toggle on ---
  console.log('  scenario: srcmap loaded, toggle on');
  {
    const context = await browser.newContext({
      viewport: RISCV_VIEWPORT,
      deviceScaleFactor: DEVICE_SCALE
    });
    const page = await context.newPage();
    await routeCdnToLocal(page);

    await page.route('**/kernel_srcmap.json', async (route) => {
      await route.fulfill({
        body: JSON.stringify(MOCK_SRCMAP),
        contentType: 'application/json; charset=utf-8'
      });
    });

    await page.goto(`${baseUrl}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });

    await loadRiscvRunner(page);

    await page.waitForFunction(() => {
      const log = document.querySelector('#eventLog')?.textContent || '';
      return log.includes('Loaded source map');
    }, null, { timeout: 30000 });

    await navigateToMemoryAndRefresh(page);

    // Enable the C Source toggle
    await page.evaluate(() => {
      const cb = document.querySelector('#memoryShowSource');
      if (cb) { cb.checked = true; cb.dispatchEvent(new Event('change')); }
      document.querySelector('#memoryRefreshBtn')?.click();
    });

    // Wait for source annotations
    await page.waitForFunction(() => {
      const el = document.querySelector('#memoryDump');
      const pre = el?.shadowRoot?.querySelector('#memoryDisasmPre');
      const text = pre?.textContent || '';
      return text.includes('_entry') || text.includes('start.c');
    }, null, { timeout: 30000 });

    await ensureMemoryTabActive(page);
    await shot(page, 'riscv_disasm_srcmap_on');

    await context.close();
  }
}

async function loadRiscvRunner(page) {
  // Wait for WASM to initialize and the default runner to fully load.
  // The default auto-load must complete before we can switch runners.
  await page.waitForFunction(() => {
    const sim = document.querySelector('#simStatus')?.textContent || '';
    return sim.includes('Cycle 0');
  }, null, { timeout: 120000 });

  // Now the dropdown should have the riscv option.
  await page.waitForFunction(() => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) return false;
    return Array.from(select.options).some((opt) => opt.value === 'riscv');
  }, null, { timeout: 30000 });

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

async function ensureMemoryTabActive(page) {
  await page.evaluate(() => {
    // Force memory tab active and hide all other tab panels.
    document.querySelectorAll('.tab-btn').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.tab === 'memoryTab');
      btn.setAttribute('aria-selected', btn.dataset.tab === 'memoryTab' ? 'true' : 'false');
    });
    document.querySelectorAll('.tab-panel').forEach((panel) => {
      panel.classList.toggle('active', panel.id === 'memoryTab');
    });
  });
  await page.waitForTimeout(300);
}

async function navigateToMemoryAndRefresh(page) {
  // Switch to memory tab and fill fields via JS to avoid overlay issues.
  await page.evaluate(() => {
    document.querySelector('[data-tab="memoryTab"]')?.click();
  });
  await page.waitForTimeout(500);
  await page.evaluate(() => {
    const start = document.querySelector('#memoryStart');
    const len = document.querySelector('#memoryLength');
    if (start) { start.value = '0x80000000'; start.dispatchEvent(new Event('input')); }
    if (len) { len.value = '256'; len.dispatchEvent(new Event('input')); }
  });
  await page.evaluate(() => {
    document.querySelector('#memoryRefreshBtn')?.click();
  });

  await page.waitForFunction(() => {
    const el = document.querySelector('#memoryDump');
    const pre = el?.shadowRoot?.querySelector('#memoryDisasmPre');
    const text = pre?.textContent || '';
    return text.includes('80000000') && text.length > 40;
  }, null, { timeout: 60000 });
}

// -------------------------------------------------------------------

async function main() {
  const { chromium } = await import('playwright');
  const webRoot = resolveWebRoot(import.meta.url);
  const server = await createStaticServer(webRoot);
  const baseUrl = serverBaseUrl(server);

  await mkdir(DOCS_DIR, { recursive: true });

  console.log(`Server running at ${baseUrl}`);

  const skipMain = process.argv.includes('--riscv-only');
  const skipRiscv = process.argv.includes('--main-only');

  try {
    if (!skipMain) {
      const browser = await chromium.launch({ headless: true });
      try { await takeMainScreenshots(browser, baseUrl); } finally { await browser.close(); }
    }
    if (!skipRiscv) {
      const browser = await chromium.launch({ headless: true });
      try { await takeRiscvScreenshots(browser, baseUrl); } finally { await browser.close(); }
    }
    console.log('\nAll screenshots updated.');
  } finally {
    server.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
