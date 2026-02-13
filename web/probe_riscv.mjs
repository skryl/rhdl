import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.'));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

page.on('console', (msg) => console.log('[console]', msg.type(), msg.text()));
page.on('pageerror', (err) => console.error('[pageerror]', err.message));

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(2000);

await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.dispatchEvent('#runnerSelect', 'change');
await page.click('#loadRunnerBtn');

await page.waitForFunction(() => {
  const text = document.querySelector('#runnerStatus')?.textContent || '';
  return text.includes('riscv') || text.includes('loaded') || text.includes('Initialized') || text.includes('Cycle');
}, { timeout: 120000 });

const out = await page.evaluate(() => {
  const sim = window.runtime?.sim;
  return {
    hasRuntime: !!sim,
    hasRunnerModeFn: typeof sim?.runner_mode,
    runnerMode: typeof sim?.runner_mode === 'function' ? sim.runner_mode?.() : 'n/a',
    hasRunnerMemExport: typeof sim?.hasExport === 'function' ? sim.hasExport('runner_mem') : 'no hasExport',
    hasRunnerLoadMemory: typeof sim?.runner_load_memory,
    hasMemoryLoad: typeof sim?.memory_load,
    hasMemoryModeFn: typeof sim?.memory_mode,
    memoryMode: typeof sim?.memory_mode === 'function' ? sim.memory_mode?.() : 'n/a',
    hasReset: typeof sim?.reset,
    runnerMemExportPtr: !!sim?.e?.runner_mem,
    runnerMemFnType: typeof sim?.e?.runner_mem,
    hasRunnerMemTransfer: !!sim?.runnerMemTransfer
  };
});

const log = await page.$eval('#eventLog', (el) => el?.textContent || '');
console.log(JSON.stringify({ out, log }, null, 2));

await browser.close();
await server.close();
