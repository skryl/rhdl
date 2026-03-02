import test from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import type { Page } from 'playwright';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

type TerminalTextElement = Element & {
  dataset?: DOMStringMap;
  value?: string;
};

async function hasMirbAsset(webRoot: string): Promise<boolean> {
  const mirbScriptPath = path.join(webRoot, 'assets', 'pkg', 'mirb.js');
  try {
    await access(mirbScriptPath);
    return true;
  } catch (_err: unknown) {
    return false;
  }
}

async function ensureTerminalOpen(page: Page): Promise<void> {
  await page.waitForSelector('#terminalPanel', { state: 'attached', timeout: 20000 });
  await page.waitForSelector('#terminalToggleBtn', { state: 'attached', timeout: 20000 });
  const hidden = await page.$eval('#terminalPanel', (panel) => (panel as HTMLElement).hidden);
  if (hidden) {
    await page.click('#terminalToggleBtn');
  }
  await page.waitForFunction(() => {
    const panel = document.querySelector('#terminalPanel');
    return panel instanceof HTMLElement && panel.hidden === false;
  }, null, { timeout: 20000 });
}

async function readTerminalOutput(page: Page): Promise<string> {
  return page.$eval(
    '#terminalOutput',
    (el) => {
      const terminalEl = el as TerminalTextElement;
      return String(terminalEl.dataset?.terminalText ?? terminalEl.value ?? terminalEl.textContent ?? '');
    }
  );
}

async function runTerminalCommand(page: Page, command: string, expectedMarker: string, timeoutMs = 60000): Promise<void> {
  await page.click('#terminalOutput');
  await page.keyboard.type(command);
  await page.keyboard.press('Enter');
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    const text = await readTerminalOutput(page);
    const commandPos = text.lastIndexOf(`$ ${command}`);

    if (commandPos >= 0) {
      const section = text.slice(commandPos);
      if (section.includes(expectedMarker)) {
        return;
      }
      if (section.toLowerCase().includes('error:')) {
        throw new Error(`Terminal command failed for "${command}":\n${section.slice(0, 600)}`);
      }
    }

    await page.waitForTimeout(200);
  }

  const tail = (await readTerminalOutput(page)).slice(-1200);
  throw new Error(`Timed out waiting for terminal marker "${expectedMarker}" after command "${command}".\nTail:\n${tail}`);
}

test('terminal mirb supports one-shot and session flows', { timeout: 300000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && npm install`)');
    return;
  }

  const webRoot = resolveWebRoot(import.meta.url);
  if (!(await hasMirbAsset(webRoot))) {
    console.warn('mirb assets are missing (install emscripten and run: `PATH="$HOME/.cargo/bin:$PATH" bundle exec rake web:build`)');
    return;
  }

  const server = await createStaticServer(webRoot);
  t.after(() => {
    server.close();
  });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (_err: unknown) {
    console.warn('Playwright browser binaries are missing (run: `cd web && npx playwright install chromium`)');
    return;
  }
  t.after(async () => {
    await browser.close();
  });

  const page = await browser.newPage();
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];

  page.on('pageerror', (err) => {
    const message = String(err?.message || err);
    if (message.includes("Failed to execute 'drawImage' on 'CanvasRenderingContext2D'")
      && message.includes('canvas element with a width or height of 0')) {
      return;
    }
    pageErrors.push(message);
  });
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      const text = msg.text();
      if (text.includes('Failed to load resource: the server responded with a status of 404')) {
        return;
      }
      consoleErrors.push(text);
    }
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#simStatus', { timeout: 20000 });
  await ensureTerminalOpen(page);

  await runTerminalCommand(page, 'irb 6 * 7', '=> 42');
  await runTerminalCommand(page, 'irb "require \'rhdl\'; RHDL.minimal_runtime?"', '=> true');
  await runTerminalCommand(page, 'mirb', 'mirb session started');
  await runTerminalCommand(page, 'n = 10', '=> 10');
  await runTerminalCommand(page, 'n + 5', '=> 15');
  await runTerminalCommand(page, 'exit', 'mirb session closed');
  await runTerminalCommand(page, 'irb 9 - 4', '=> 5');

  const terminalOutput = await readTerminalOutput(page);
  assert.doesNotMatch(terminalOutput || '', /mirb execution timed out/);
  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
