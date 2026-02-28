import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStaticServer,
  resolveWebRoot,
  serverBaseUrl
} from './browser_test_harness';

const WEBGL_LAUNCH_ARGS = ['--use-angle=swiftshader', '--enable-webgl', '--ignore-gpu-blocklist'];

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

test('schematic webgl renderer emits wire draws with line divisor resets', { timeout: 180000 }, async (t) => {
  let chromium;
  try {
    ({ chromium } = await import('playwright'));
  } catch (_err) {
    t.skip('Playwright is not installed (run: `cd web && npm install`)');
    return;
  }

  const webRoot = resolveWebRoot(import.meta.url);
  const server = await createStaticServer(webRoot);
  t.after(() => {
    server.close();
  });

  let browser;
  try {
    browser = await chromium.launch({ headless: true, args: WEBGL_LAUNCH_ARGS });
  } catch (_err) {
    t.skip('Playwright browser binaries are missing (run: `cd web && npx playwright install chromium`)');
    return;
  }
  t.after(async () => {
    await browser.close();
  });

  const page = await browser.newPage({ viewport: { width: 1920, height: 1600 } });
  const pageErrors = [];
  const consoleErrors = [];

  await page.addInitScript(() => {
    const probe = {
      wrappedContexts: 0,
      lineDrawCalls: 0,
      lineDivisorZeroCalls: 0
    };
    window.__RHDL_WEBGL_WIRE_PROBE__ = probe;

    const proto = globalThis.HTMLCanvasElement?.prototype;
    if (!proto || typeof proto.getContext !== 'function') {
      return;
    }
    const originalGetContext = proto.getContext;
    proto.getContext = function patchedGetContext(type, ...args) {
      const ctx = originalGetContext.call(this, type, ...args);
      if (type !== 'webgl2' || !ctx || ctx.__rhdlWireProbeWrapped) {
        return ctx;
      }
      ctx.__rhdlWireProbeWrapped = true;
      probe.wrappedContexts += 1;

      const originalDivisor = typeof ctx.vertexAttribDivisor === 'function'
        ? ctx.vertexAttribDivisor.bind(ctx)
        : null;
      if (originalDivisor) {
        ctx.vertexAttribDivisor = function patchedDivisor(index, divisor) {
          if (index >= 0 && index <= 4 && divisor === 0) {
            probe.lineDivisorZeroCalls += 1;
          }
          return originalDivisor(index, divisor);
        };
      }

      const originalDrawArrays = typeof ctx.drawArrays === 'function'
        ? ctx.drawArrays.bind(ctx)
        : null;
      if (originalDrawArrays) {
        ctx.drawArrays = function patchedDrawArrays(mode, first, count) {
          if (mode === ctx.TRIANGLE_STRIP && count === 4) {
            probe.lineDrawCalls += 1;
          }
          return originalDrawArrays(mode, first, count);
        };
      }

      return ctx;
    };
  });

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
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  await page.click('#loadRunnerBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('Apple II System Runner');
  }, null, { timeout: 120000 });

  await page.click('[data-tab="componentGraphTab"]');
  await page.waitForFunction(() => {
    const panel = document.querySelector('#componentGraphTab');
    return !!panel && panel.classList.contains('active');
  }, null, { timeout: 120000 });
  await page.waitForSelector('#componentVisual canvas', { state: 'attached', timeout: 120000 });
  await page.waitForFunction(() => {
    const state = window.__RHDL_UX_STATE__;
    const graph = state?.components?.graph;
    const renderList = graph?.renderList;
    if (!renderList || !Array.isArray(renderList.wires) || renderList.wires.length === 0) {
      return false;
    }
    return state?.components?.graphRenderBackend === 'webgl';
  }, null, { timeout: 120000 });

  await page.click('#componentGraphZoomInBtn');
  await page.click('#componentGraphZoomOutBtn');

  const probeState = await page.evaluate(() => {
    const state = window.__RHDL_UX_STATE__;
    const graph = state?.components?.graph;
    const wireCount = Array.isArray(graph?.renderList?.wires) ? graph.renderList.wires.length : 0;
    const probe = window.__RHDL_WEBGL_WIRE_PROBE__ || {};
    return {
      backend: state?.components?.graphRenderBackend || null,
      wireCount,
      wrappedContexts: Number(probe.wrappedContexts || 0),
      lineDrawCalls: Number(probe.lineDrawCalls || 0),
      lineDivisorZeroCalls: Number(probe.lineDivisorZeroCalls || 0)
    };
  });

  assert.equal(probeState.backend, 'webgl', 'probe should run in webgl mode');
  assert.ok(probeState.wireCount > 0, 'schematic should include wire elements');
  assert.ok(probeState.wrappedContexts > 0, 'probe should wrap at least one WebGL context');
  assert.ok(probeState.lineDrawCalls > 0, 'wire pass should emit TRIANGLE_STRIP line draws');
  assert.ok(
    probeState.lineDivisorZeroCalls >= 5,
    `expected line attribute divisor resets, got ${probeState.lineDivisorZeroCalls}`
  );

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
