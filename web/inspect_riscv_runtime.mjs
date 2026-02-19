import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.'));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

const logs = [];
page.on('console', (msg) => logs.push(`${msg.type()}: ${msg.text()}`));
page.on('pageerror', (err) => logs.push(`PAGEERROR: ${err.message}`));

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.click('#loadRunnerBtn');

await page.waitForTimeout(2000);

const snap = await page.evaluate(() => {
  const sim = window.runtime?.sim;
  const status = document.querySelector('#simStatus')?.textContent;
  const runner = document.querySelector('#runnerStatus')?.textContent;
  const eventLog = document.querySelector('#eventLog')?.textContent || '';
  return {
    status,
    runner,
    hasRuntimeSim: !!window.runtime?.sim,
    runtimeKeys: window.runtime ? Object.keys(window.runtime) : [],
    hasRunnerMode: !!(sim && typeof sim.runner_mode === 'function'),
    hasRunnerLoadMemory: typeof sim?.runner_load_memory,
    hasRunnerMem: typeof sim?.runner_mem,
    hasMemoryMode: typeof sim?.memory_mode,
    simPrototypePrefix: sim ? Object.getOwnPropertyNames(Object.getPrototypeOf(sim)).slice(0, 30) : [],
    eventLogTail: eventLog.slice(-5000)
  };
});

console.log(JSON.stringify(snap, null, 2));
console.log('--- logs ---');
console.log(logs.slice(-120).join('\n'));

await browser.close();
await server.close();
