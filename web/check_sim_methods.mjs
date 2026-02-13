import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.', ''));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('#simStatus', { timeout: 20000 });
await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.click('#loadRunnerBtn');
await page.waitForFunction(() => {
  const t = document.querySelector('#simStatus')?.textContent || '';
  return t.includes('Cycle 0');
}, null, { timeout: 120000 });
await page.waitForTimeout(500);

const out = await page.evaluate(() => {
  const sim = window.runtime?.sim;
  const keys = sim ? Object.getOwnPropertyNames(Object.getPrototypeOf(sim)).filter((n) => n.includes('runner') || n.includes('memory') || n.includes('mode') || n.includes('support')) : [];
  return {
    hasRunnerMode: !!(sim && typeof sim.runner_mode === 'function'),
    runnerModeValue: sim?.runner_mode?.(),
    hasRunnerLoadMemory: typeof sim?.runner_load_memory,
    hasRunnerLoadRom: typeof sim?.runner_load_rom,
    hasMemoryLoad: typeof sim?.memory_load,
    memoryModeType: sim?.memory_mode?.(),
    hasMemoryMode: typeof sim?.memory_mode,
    supportsRunnerApi: (sim?.runner_mode?.() === true || (typeof sim?.runner_read_memory === 'function' && typeof sim?.runner_write_memory === 'function')),
    supportsGeneric: (typeof sim?.memory_mode === 'function' && sim?.memory_mode?.() != null),
    prototypeKeys: keys.slice(0, 200),
  };
});

console.log(out);

await browser.close();
await server.close();
