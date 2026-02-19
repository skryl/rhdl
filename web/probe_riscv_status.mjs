import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.'));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

page.on('console', (msg) => console.log('[console]', msg.type(), msg.text()));
page.on('pageerror', (err) => console.error('[pageerror]', err.message));
page.on('requestfailed', req=>console.log('[reqfail]', req.url(), req.failure()?.errorText));

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForTimeout(2000);

await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.dispatchEvent('#runnerSelect', 'change');
await page.click('#loadRunnerBtn');

for (let i=0; i<30; i++) {
  await page.waitForTimeout(1000);
  const status = await page.$eval('#runnerStatus', (el) => el?.textContent || '');
  const sim = await page.$eval('#simStatus', (el) => el?.textContent || '');
  console.log('t', i, 'runnerStatus=', status, 'simStatus=', sim);
}

const hasStatus = await page.$eval('#eventLog', (el) => el?.textContent || '');
console.log('EVENT LOG END\n'+hasStatus);

await browser.close();
await server.close();
