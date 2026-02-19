import path from 'node:path';
import { chromium } from 'playwright';
import { createStaticServer, serverBaseUrl } from './test/integration/browser_test_harness.mjs';

const server = await createStaticServer(path.resolve('.'));
const base = serverBaseUrl(server);
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage();
const entries=[];
page.on('console', (msg)=>entries.push(`${Date.now()}: [${msg.type()}] ${msg.text()}`));
page.on('pageerror', (err)=>entries.push(`${Date.now()}: [pageerror] ${err.message}`));
page.on('requestfailed', (req)=>entries.push(`${Date.now()}: [requestfailed] ${req.url()} ${req.failure()?.errorText}`));
await page.goto(`${base}/index.html`, { waitUntil: 'domcontentloaded' });
await page.selectOption('#backendSelect','interpreter');
await page.dispatchEvent('#backendSelect','change');
await page.selectOption('#runnerSelect','riscv');
await page.click('#loadRunnerBtn');

await page.waitForTimeout(12000);

console.log(entries.join('\n'));

await browser.close();
await server.close();
