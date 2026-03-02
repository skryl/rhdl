import test from 'node:test';
import assert from 'node:assert/strict';
import type { Page } from 'playwright';

import {
  createStaticServer,
  resolveWebRoot,
  serverBaseUrl
} from './browser_test_harness';

const BENIGN_PAGE_ERRORS = [
  'Failed to execute \'drawImage\' on \'CanvasRenderingContext2D\': The image argument is a canvas element with a width or height of 0.'
];

type GraphViewport = {
  x?: number;
  y?: number;
  scale?: number;
};

type UxState = {
  components?: {
    graph?: {
      canvas?: unknown;
      viewport?: GraphViewport;
    };
  };
};

type WindowWithUxState = Window & {
  __RHDL_UX_STATE__?: UxState;
};

type ViewportSnapshot = {
  x: number;
  y: number;
  scale: number;
};

type CanvasPoint = {
  x: number;
  y: number;
  width: number;
  height: number;
  onScreen: boolean;
  targetIsCanvas: boolean;
};

function readGraphViewport(page: Page): Promise<ViewportSnapshot | null> {
  return page.evaluate(() => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    if (!viewport) {
      return null;
    }
    return {
      x: Number(viewport.x || 0),
      y: Number(viewport.y || 0),
      scale: Number(viewport.scale || 1)
    };
  });
}

test('schematic viewer supports wheel zoom and drag pan in browser', { timeout: 180000 }, async (t) => {
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

  const page = await browser.newPage({ viewport: { width: 1920, height: 1600 } });
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
  await page.waitForSelector('#simStatus', { timeout: 20000 });

  await page.click('#loadRunnerBtn');
  await page.waitForFunction(() => {
    const text = document.querySelector('#runnerStatus')?.textContent || '';
    return text.includes('Apple II System Runner');
  }, null, { timeout: 120000 });

  let point: CanvasPoint | null = null;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    await page.click('[data-tab="componentGraphTab"]');
    await page.waitForFunction(() => {
      const panel = document.querySelector('#componentGraphTab');
      return !!panel && panel.classList.contains('active');
    }, null, { timeout: 120000 });
    await page.waitForSelector('#componentVisual canvas', { state: 'attached', timeout: 120000 });
    await page.waitForFunction(() => {
      const graph = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph;
      const viewport = graph?.viewport;
      return !!graph?.canvas && !!viewport && Number.isFinite(Number(viewport.scale));
    }, null, { timeout: 120000 });

    point = await page.evaluate(() => {
      const element = document.querySelector('#componentVisual canvas');
      if (!element) return null;
      const rect = element.getBoundingClientRect();
      const pad = 40;
      const x = rect.left + Math.min(pad, Math.max(0, rect.width - pad));
      const y = rect.top + Math.min(pad, Math.max(0, rect.height - pad));
      const onScreen = (
        x >= 0 &&
        y >= 0 &&
        x <= window.innerWidth &&
        y <= window.innerHeight
      );
      const target = document.elementFromPoint(x, y);
      const targetIsCanvas = !!target && target.tagName === 'CANVAS';
      return { x, y, width: rect.width, height: rect.height, onScreen, targetIsCanvas };
    }) as CanvasPoint | null;

    if (point && point.width > 30 && point.height > 30 && point.onScreen && point.targetIsCanvas) {
      break;
    }
    await page.waitForTimeout(250);
  }

  assert.ok(point && point.width > 30 && point.height > 30, 'schematic canvas should be present');
  assert.equal(point.onScreen, true, 'schematic interaction point should be on screen');
  assert.equal(point.targetIsCanvas, true, 'schematic interaction point should target the canvas');

  const initialViewport = await readGraphViewport(page);
  assert.ok(initialViewport, 'initial viewport should be available');
  const initial = initialViewport as ViewportSnapshot;

  await page.click('#componentGraphZoomInBtn');
  await page.waitForFunction((initialScale) => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    return Number(viewport?.scale || 1) > (Number(initialScale) + 0.01);
  }, initial.scale, { timeout: 120000 });
  const afterZoomInBtn = await readGraphViewport(page);
  assert.ok(afterZoomInBtn && afterZoomInBtn.scale > initial.scale, 'zoom-in button should increase scale');
  const afterZoomIn = afterZoomInBtn as ViewportSnapshot;

  await page.click('#componentGraphZoomOutBtn');
  await page.waitForFunction((zoomedScale) => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    return Number(viewport?.scale || 1) < (Number(zoomedScale) - 0.01);
  }, afterZoomIn.scale, { timeout: 120000 });
  const afterZoomOutBtn = await readGraphViewport(page);
  assert.ok(afterZoomOutBtn && afterZoomOutBtn.scale < afterZoomIn.scale, 'zoom-out button should decrease scale');
  const afterZoomOut = afterZoomOutBtn as ViewportSnapshot;

  await page.mouse.move(point.x, point.y);
  await page.mouse.wheel(0, -800);
  await page.waitForFunction((initialScale) => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    return Number(viewport?.scale || 1) > (Number(initialScale) + 0.01);
  }, afterZoomOut.scale, { timeout: 120000 });

  const zoomedViewport = await readGraphViewport(page);
  assert.ok(zoomedViewport, 'zoomed viewport should be available');
  assert.ok(zoomedViewport.scale > initial.scale, 'wheel should increase zoom scale');
  const zoomed = zoomedViewport as ViewportSnapshot;

  await page.mouse.move(point.x, point.y);
  await page.mouse.down();
  await page.mouse.move(point.x + 140, point.y + 90, { steps: 12 });
  await page.mouse.up();
  await page.waitForFunction((prev) => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    if (!viewport) return false;
    return (
      Math.abs(Number(viewport.x || 0) - Number(prev.x || 0)) > 5 ||
      Math.abs(Number(viewport.y || 0) - Number(prev.y || 0)) > 5
    );
  }, zoomed, { timeout: 120000 });

  const pannedViewport = await readGraphViewport(page);
  assert.ok(pannedViewport, 'panned viewport should be available');
  assert.ok(
    Math.abs(pannedViewport.x - zoomed.x) > 5 || Math.abs(pannedViewport.y - zoomed.y) > 5,
    'drag should move viewport translation'
  );
  const panned = pannedViewport as ViewportSnapshot;

  await page.click('#componentGraphResetViewBtn');
  await page.waitForFunction((initial) => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    if (!viewport) return false;
    return (
      Math.abs(Number(viewport.scale || 1) - Number(initial.scale || 1)) < 0.01 &&
      Math.abs(Number(viewport.x || 0) - Number(initial.x || 0)) < 1 &&
      Math.abs(Number(viewport.y || 0) - Number(initial.y || 0)) < 1
    );
  }, initial, { timeout: 120000 });

  const resetViewport = await readGraphViewport(page);
  assert.ok(resetViewport, 'reset viewport should be available');
  assert.ok(Math.abs(resetViewport.scale - initial.scale) < 0.01, 'reset should restore default scale');
  assert.ok(Math.abs(resetViewport.x - initial.x) < 1, 'reset should restore default x translation');
  assert.ok(Math.abs(resetViewport.y - initial.y) < 1, 'reset should restore default y translation');

  for (let i = 0; i < 12; i += 1) {
    await page.click('#componentGraphZoomOutBtn');
  }
  await page.waitForFunction(() => {
    const viewport = (window as WindowWithUxState).__RHDL_UX_STATE__?.components?.graph?.viewport;
    return Number(viewport?.scale || 1) < 0.2;
  }, null, { timeout: 120000 });
  const deepZoomOutViewport = await readGraphViewport(page);
  assert.ok(deepZoomOutViewport && deepZoomOutViewport.scale < 0.2, 'zoom-out button should support scales below previous floor');

  assert.deepEqual(pageErrors, [], `Unhandled page errors: ${pageErrors.join(' | ')}`);
  assert.deepEqual(consoleErrors, [], `Console errors: ${consoleErrors.join(' | ')}`);
});
