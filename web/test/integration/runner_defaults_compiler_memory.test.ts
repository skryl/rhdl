import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

const EXPECTED_RUNNERS = ['cpu', 'mos6502', 'apple2', 'gameboy', 'riscv', 'riscv_linux'];
const DEFAULT_BACKEND = 'compiler';
const DEFAULT_MEMORY_LENGTH = 768;
const DEFAULT_TRACE_ENABLED_ON_LOAD = false;

type RunnerPreset = {
  preferredBackend?: string;
  io?: {
    memory?: {
      dumpLength?: number;
    };
  };
  defaults?: {
    traceEnabled?: boolean;
  };
  traceEnabledOnLoad?: boolean;
};

type RunnerSummary = {
  preferredBackend: string | null;
  dumpLength: number | null;
  traceEnabledOnLoad: boolean;
};

type RunnerSummaryMap = Record<string, RunnerSummary>;

test('all runner presets default to compiler backend, 768 memory length, and trace disabled on load', { timeout: 120000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err: unknown) {
    console.warn('Playwright is not installed (run: `cd web && bun install`)');
    return;
  }

  const webRoot = resolveWebRoot(import.meta.url);
  const server = await createStaticServer(webRoot);
  t.after(() => {
    server.close();
  });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
  } catch (_err: unknown) {
    console.warn('Playwright browser binaries are missing (run: `cd web && bunx playwright install chromium`)');
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
    if (BENIGN_PAGE_ERRORS.some((entry) => message.includes(entry))) {
      return;
    }
    pageErrors.push(message);
  });
  page.on('console', (msg) => {
    if (msg.type() !== 'error') {
      return;
    }
    const text = msg.text();
    if (text.includes('Failed to load resource: the server responded with a status of 404')) {
      return;
    }
    consoleErrors.push(text);
  });

  await page.goto(`${serverBaseUrl(server)}/index.html`, { waitUntil: 'domcontentloaded' });
  await page.waitForSelector('#runnerSelect', { timeout: 20000 });

  await page.waitForFunction((expected) => {
    const select = document.querySelector('#runnerSelect');
    if (!(select instanceof HTMLSelectElement)) {
      return false;
    }
    const available = new Set(Array.from(select.options).map((opt) => opt.value));
    return expected.every((id) => available.has(id));
  }, EXPECTED_RUNNERS, { timeout: 120000 });

  const defaults = await page.evaluate(async (): Promise<RunnerSummaryMap> => {
    // @ts-expect-error browser-context dynamic import; not resolvable by Node TS
    const module = await import('./app/components/runner/config/generated_presets') as {
      GENERATED_RUNNER_PRESETS?: Record<string, RunnerPreset>;
    };
    const presets = module.GENERATED_RUNNER_PRESETS || {};
    const summary: RunnerSummaryMap = {};
    for (const [id, preset] of Object.entries(presets)) {
      const traceEnabledOnLoad = Object.prototype.hasOwnProperty.call(preset || {}, 'traceEnabledOnLoad')
        ? preset?.traceEnabledOnLoad === true
        : (preset?.defaults?.traceEnabled === true);
      summary[id] = {
        preferredBackend: preset?.preferredBackend ?? null,
        dumpLength: preset?.io?.memory?.dumpLength ?? null,
        traceEnabledOnLoad
      };
    }
    return summary;
  });

  for (const runnerId of EXPECTED_RUNNERS) {
    assert.equal(defaults[runnerId]?.preferredBackend, DEFAULT_BACKEND, `${runnerId} preferred backend`);
    assert.equal(defaults[runnerId]?.dumpLength, DEFAULT_MEMORY_LENGTH, `${runnerId} memory dump length`);
    assert.equal(
      defaults[runnerId]?.traceEnabledOnLoad,
      DEFAULT_TRACE_ENABLED_ON_LOAD,
      `${runnerId} trace enabled on load`
    );
  }

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
