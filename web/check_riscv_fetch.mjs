import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.', ''));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

page.on('request', (req) => {
  if (req.url().includes('kernel.bin')) {
    console.log('request', req.method(), req.url());
  }
});

page.on('requestfinished', (req) => {
  if (req.url().includes('kernel.bin')) {
    const response = req.response();
    console.log('responseType', typeof response, response == null ? null : Object.getPrototypeOf(response).constructor.name);
    console.log('respKeys', response == null ? [] : Object.keys(response));
    console.log('responseStatus', response?.status, response?.status?.());
  }
});

page.on('console', (msg) => {
  const txt = msg.text();
  if (txt.includes('kernel.bin') || txt.includes('Default bin') || txt.includes('Loaded default')) {
    console.log('console:', txt);
  }
});

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('#simStatus', { timeout: 20000 });
await page.selectOption('#backendSelect', 'interpreter');
await page.dispatchEvent('#backendSelect', 'change');
await page.selectOption('#runnerSelect', 'riscv');
await page.click('#loadRunnerBtn');
await page.waitForFunction(() => {
  const text = document.querySelector('#simStatus')?.textContent || '';
  return text.includes('Cycle 0');
}, null, { timeout: 120000 });

await page.waitForTimeout(3000);
const log = await page.$eval('#eventLog', (el) => el?.textContent || '');
console.log('EVENT_LOG\n' + log);

await browser.close();
await server.close();
