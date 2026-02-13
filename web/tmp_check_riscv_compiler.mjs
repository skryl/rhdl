import { chromium } from 'playwright';
import { createStaticServer } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(process.cwd());
const base = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();

page.on('console', (msg) => {
  const text = msg.text();
  if (text.includes('Default bin load') || text.includes('Loaded default') || text.includes('Failed') || text.includes('riscv')) {
    console.log('console:', text);
  }
});

await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.waitForSelector('#simStatus', { timeout: 20000 });
await page.selectOption('#backendSelect', 'compiler');
await page.selectOption('#runnerSelect', 'riscv');
await page.click('#loadRunnerBtn');

await page.waitForFunction(() => {
  const text = document.querySelector('#simStatus')?.textContent || '';
  return text.includes('Cycle 0');
}, null, { timeout: 120000 });

const log = await page.$eval('#eventLog', (el) => el?.textContent || '');
console.log('EVENT_SNIP', log.match(/Loaded default bin \(main\) .*kernel\.bin/)?.[0] || 'MISSING');

await browser.close();
await server.close();
