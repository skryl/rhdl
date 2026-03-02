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

type WireProbe = {
  wrappedContexts: number;
  lineDrawCalls: number;
  lineDivisorZeroCalls: number;
};

type UxState = {
  components?: {
    graphRenderBackend?: string;
    graph?: {
      renderList?: {
        wires?: unknown[];
      };
    };
  };
};

type WindowWithProbeState = Window & {
  __RHDL_WEBGL_WIRE_PROBE__?: WireProbe;
  __RHDL_UX_STATE__?: UxState;
};

type ProbeableWebGL2Context = WebGL2RenderingContext & {
  __rhdlWireProbeWrapped?: boolean;
};

test('schematic webgl renderer emits wire draws with line divisor resets', { timeout: 180000 }, async (t) => {
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
    browser = await chromium.launch({ headless: true, args: WEBGL_LAUNCH_ARGS });
  } catch (_err: unknown) {
    console.warn('Playwright browser binaries are missing (run: `cd web && bunx playwright install chromium`)');
    return;
  }
  t.after(async () => {
    await browser.close();
  });

  const page = await browser.newPage({ viewport: { width: 1920, height: 1600 } });
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];

  await page.addInitScript(() => {
    const probe: WireProbe = {
      wrappedContexts: 0,
      lineDrawCalls: 0,
      lineDivisorZeroCalls: 0
    };
    (window as WindowWithProbeState).__RHDL_WEBGL_WIRE_PROBE__ = probe;

    const proto = globalThis.HTMLCanvasElement?.prototype;
    if (!proto || typeof proto.getContext !== 'function') {
      return;
    }

    const originalGetContext = proto.getContext;
    proto.getContext = function patchedGetContext(this: HTMLCanvasElement, type: unknown, ...args: unknown[]) {
      const context = Reflect.apply(
        originalGetContext as (...innerArgs: unknown[]) => unknown,
        this,
        [type, ...args]
      );

      if (type !== 'webgl2' || !context || typeof context !== 'object') {
        return context as ReturnType<typeof originalGetContext>;
      }

      const ctx = context as ProbeableWebGL2Context;
      if (ctx.__rhdlWireProbeWrapped) {
        return context as ReturnType<typeof originalGetContext>;
      }

      ctx.__rhdlWireProbeWrapped = true;
      probe.wrappedContexts += 1;

      const originalDivisor = typeof ctx.vertexAttribDivisor === 'function'
        ? ctx.vertexAttribDivisor.bind(ctx)
        : null;
      if (originalDivisor) {
        ctx.vertexAttribDivisor = function patchedDivisor(index: number, divisor: number) {
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
        ctx.drawArrays = function patchedDrawArrays(mode: number, first: number, count: number) {
          if (mode === ctx.TRIANGLE_STRIP && count === 4) {
            probe.lineDrawCalls += 1;
          }
          return originalDrawArrays(mode, first, count);
        };
      }

      return context as ReturnType<typeof originalGetContext>;
    } as typeof proto.getContext;
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
    const state = (window as WindowWithProbeState).__RHDL_UX_STATE__;
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
    const state = (window as WindowWithProbeState).__RHDL_UX_STATE__;
    const graph = state?.components?.graph;
    const wireCount = Array.isArray(graph?.renderList?.wires) ? graph.renderList.wires.length : 0;
    const probe = (window as WindowWithProbeState).__RHDL_WEBGL_WIRE_PROBE__;
    return {
      backend: state?.components?.graphRenderBackend || null,
      wireCount,
      wrappedContexts: Number(probe?.wrappedContexts || 0),
      lineDrawCalls: Number(probe?.lineDrawCalls || 0),
      lineDivisorZeroCalls: Number(probe?.lineDivisorZeroCalls || 0)
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
