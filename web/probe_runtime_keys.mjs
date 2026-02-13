import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.'));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(1000);
await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.dispatchEvent('#runnerSelect', 'change');
await page.click('#loadRunnerBtn');
await page.waitForFunction(() => (document.querySelector('#simStatus')?.textContent || '').includes('Cycle 0'), { timeout: 120000});

const out = await page.evaluate(() => {
  const runtime = window.runtime;
  const candidates = runtime ? Object.keys(runtime) : [];
  const sim = runtime?.sim;
  return {
    runtimeType: runtime ? runtime.constructor?.name : null,
    runtimeKeys: candidates,
    simType: sim?.constructor?.name,
    simKeys: sim ? Object.getOwnPropertyNames(sim) : [],
    simProto: sim ? Object.getOwnPropertyNames(Object.getPrototypeOf(sim)).slice(0, 200) : [],
    runnerModeFn: typeof sim?.runner_mode,
    memModeFn: typeof sim?.memory_mode,
    simStatusText: document.querySelector('#simStatus')?.textContent || '',
    runnerStatusText: document.querySelector('#runnerStatus')?.textContent || ''
  };
});
console.log(JSON.stringify(out, null, 2));
await browser.close();
await server.close();
