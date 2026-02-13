import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.'));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

page.on('console', (msg) => console.log('[console]', msg.type(), msg.text()));

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1200);
await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.dispatchEvent('#runnerSelect', 'change');
await page.click('#loadRunnerBtn');
await page.waitForFunction(() => (document.querySelector('#simStatus')?.textContent || '').includes('Cycle 0'), { timeout: 120000});

const res = await page.evaluate(async () => {
  const sim = window.runtime?.sim;
  const resp = await fetch('./assets/fixtures/riscv/software/bin/kernel.bin');
  const bytes = new Uint8Array(await resp.arrayBuffer());
  const hasRunner = typeof sim?.runner_load_memory === 'function';
  const hasRunnerMem = sim?.hasExport?.('runner_mem');
  const hasMemLoad = typeof sim?.memory_load === 'function';
  const before = {
    hasRunner,
    hasRunnerMem,
    hasMemLoad,
    runnerMode: sim?.runner_mode?.(),
  };
  let result = null;
  let error = null;
  try {
    result = sim?.runner_load_memory?.(bytes, 0x80000000, { isRom: false });
  } catch (err) {
    error = String(err);
  }
  return { before, hasResponseOK: resp.ok, len: bytes.length, result, error };
});

console.log(res);

await browser.close();
await server.close();
