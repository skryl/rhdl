#!/usr/bin/env node
// Captures screenshots of the D3/WebGL schematic renderer at various zoom/pan states.
// Usage: node web/test/integration/screenshot_schematic.mjs

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdir, writeFile } from 'node:fs/promises';
import { execSync } from 'node:child_process';
import {
  createStaticServer,
  serverBaseUrl,
  resolveWebRoot
} from './browser_test_harness.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const screenshotDir = path.resolve(__dirname, '..', '..', '..', 'docs', 'screenshots');

const curlCache = new Map();
function curlFetch(url) {
  if (curlCache.has(url)) return curlCache.get(url);
  try {
    const b = execSync(`curl -sL "${url}"`, { maxBuffer: 20 * 1024 * 1024, timeout: 30000 });
    curlCache.set(url, b);
    return b;
  } catch (_) { return null; }
}

async function main() {
  const { chromium } = await import('playwright');
  const webRoot = resolveWebRoot(import.meta.url);
  const server = await createStaticServer(webRoot);
  const baseUrl = serverBaseUrl(server);
  console.log(`Static server at ${baseUrl}`);

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, bypassCSP: true });
  const page = await context.newPage();

  await page.route('https://cdn.jsdelivr.net/**', async (route) => {
    const body = curlFetch(route.request().url());
    if (body) route.fulfill({ status: 200, headers: { 'content-type': 'text/javascript; charset=utf-8', 'access-control-allow-origin': '*', 'cross-origin-resource-policy': 'cross-origin' }, body });
    else route.abort('failed');
  });
  await page.route('https://fonts.googleapis.com/**', async (route) => {
    const body = curlFetch(route.request().url());
    if (body) route.fulfill({ status: 200, headers: { 'content-type': 'text/css', 'access-control-allow-origin': '*', 'cross-origin-resource-policy': 'cross-origin' }, body });
    else route.abort('failed');
  });
  await page.route('https://fonts.gstatic.com/**', async (route) => {
    const body = curlFetch(route.request().url());
    if (body) route.fulfill({ status: 200, headers: { 'content-type': 'font/woff2', 'access-control-allow-origin': '*', 'cross-origin-resource-policy': 'cross-origin' }, body });
    else route.abort('failed');
  });

  // Disable WebGL (headless SwiftShader doesn't render SDF shaders correctly)
  await page.addInitScript(() => {
    const orig = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(type, ...args) {
      if (type === 'webgl2' || type === 'webgl') return null;
      return orig.call(this, type, ...args);
    };
  });

  page.on('pageerror', () => {});
  page.on('console', () => {});

  try {
    await mkdir(screenshotDir, { recursive: true });

    console.log('Loading app...');
    await page.goto(`${baseUrl}/index.html`, { waitUntil: 'domcontentloaded' });
    await page.waitForSelector('#simStatus', { timeout: 30000 });
    await page.waitForTimeout(3000);

    console.log('Loading runner...');
    await page.click('#loadRunnerBtn');
    for (let i = 0; i < 60; i++) {
      await page.waitForTimeout(2000);
      const rs = await page.textContent('#runnerStatus');
      const ss = await page.textContent('#simStatus');
      if ((rs || '').includes('Runner') && ((ss || '').includes('Cycle') || (ss || '').includes('PAUSED'))) {
        console.log(`Runner loaded at ${(i + 1) * 2}s`);
        break;
      }
    }

    // Navigate to schematic tab
    console.log('Opening schematic tab...');
    await page.click('[data-tab="componentGraphTab"]');
    await page.waitForTimeout(4000);

    // Helper: render schematic to a standalone offscreen canvas and return PNG data URL
    async function captureSchematic({ focusId, showChildren, width, height, viewport, label }) {
      console.log(`Rendering: ${label} (focus=${focusId}, ${width}x${height}, vp=${JSON.stringify(viewport)})`);
      const dataUrl = await page.evaluate(({ focusId, showChildren, width, height, viewport }) => {
        const state = window.__RHDL_UX_STATE__;
        const model = state.components.model;
        if (!model) return null;

        // Import modules from existing graph handle
        const graph = state.components.graph;
        if (!graph) return null;

        // Create a fresh offscreen canvas
        const offscreen = document.createElement('canvas');
        offscreen.width = width;
        offscreen.height = height;
        const ctx = offscreen.getContext('2d');
        if (!ctx) return null;

        // Get the renderList from the graph handle
        const renderList = graph.renderList;
        if (!renderList) return null;

        // Compute bounding box of all elements
        const all = [...renderList.symbols, ...renderList.nets, ...renderList.pins];
        if (all.length === 0) return null;

        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const el of all) {
          const hw = (el.width || 100) / 2;
          const hh = (el.height || 50) / 2;
          if (el.x - hw < minX) minX = el.x - hw;
          if (el.y - hh < minY) minY = el.y - hh;
          if (el.x + hw > maxX) maxX = el.x + hw;
          if (el.y + hh > maxY) maxY = el.y + hh;
        }

        // Auto-fit viewport with padding
        const pad = 30;
        const contentW = maxX - minX + pad * 2;
        const contentH = maxY - minY + pad * 2;
        const fitScale = Math.min(width / contentW, height / contentH, 3);

        let vp;
        if (viewport) {
          // Apply viewport adjustments relative to fit
          const baseScale = fitScale * (viewport.scaleMul || 1);
          const baseTx = (width - contentW * fitScale) / 2 - (minX - pad) * fitScale;
          const baseTy = (height - contentH * fitScale) / 2 - (minY - pad) * fitScale;
          vp = {
            scale: baseScale,
            x: baseTx * (viewport.scaleMul || 1) + (viewport.panX || 0),
            y: baseTy * (viewport.scaleMul || 1) + (viewport.panY || 0)
          };
          // Recenter when zooming
          if (viewport.scaleMul && viewport.scaleMul !== 1) {
            vp.x = width / 2 - (width / 2 - baseTx) * (viewport.scaleMul);
            vp.y = height / 2 - (height / 2 - baseTy) * (viewport.scaleMul);
            vp.x += (viewport.panX || 0);
            vp.y += (viewport.panY || 0);
          }
        } else {
          vp = {
            scale: fitScale,
            x: (width - contentW * fitScale) / 2 - (minX - pad) * fitScale,
            y: (height - contentH * fitScale) / 2 - (minY - pad) * fitScale
          };
        }

        // Draw background
        ctx.fillStyle = '#001513';
        ctx.fillRect(0, 0, width, height);

        // Apply viewport transform
        ctx.setTransform(vp.scale, 0, 0, vp.scale, vp.x, vp.y);

        // Get palette
        const palette = {
          bg: '#001513', componentBg: '#0d2b28', componentBorder: '#4f7d6d',
          componentText: '#d4e7c5', focusBg: '#0a3530', focusBorder: '#6aaf8d',
          memoryBg: '#1a2f3a', opBg: '#1a3025', ioBg: '#0d2520', ioBorder: '#4f9d7d',
          netBg: '#0d2b28', netBorder: '#4f7d6d', netText: '#d4e7c5',
          pinBg: '#1a3a30', pinBorder: '#4f7d6d',
          wire: '#4f7d6d', wireActive: '#6aaf8d', wireToggle: '#ffa726',
          selected: '#ffffff', text: '#d4e7c5'
        };

        // Draw wires (polyline through ELK bend points when available)
        for (const wire of renderList.wires) {
          ctx.strokeStyle = wire.active ? palette.wireActive : palette.wire;
          ctx.lineWidth = wire.bus ? 2.4 : 1.4;
          ctx.lineJoin = 'round';
          ctx.lineCap = 'round';
          if (wire.bidir) ctx.setLineDash([4, 3]);
          ctx.beginPath();

          if (Array.isArray(wire.bendPoints) && wire.bendPoints.length >= 2) {
            ctx.moveTo(wire.bendPoints[0].x, wire.bendPoints[0].y);
            for (let i = 1; i < wire.bendPoints.length; i++) {
              ctx.lineTo(wire.bendPoints[i].x, wire.bendPoints[i].y);
            }
          } else {
            const src = renderList.byId.get(wire.sourceId);
            const tgt = renderList.byId.get(wire.targetId);
            if (!src || !tgt) { ctx.setLineDash([]); continue; }
            ctx.moveTo(src.x, src.y);
            ctx.lineTo(tgt.x, tgt.y);
          }

          ctx.stroke();
          if (wire.bidir) ctx.setLineDash([]);
        }

        // Draw symbols
        for (const sym of renderList.symbols) {
          const hw = (sym.width || 100) / 2;
          const hh = (sym.height || 50) / 2;
          const type = sym.type || 'component';
          ctx.fillStyle = type === 'memory' ? palette.memoryBg : type === 'op' ? palette.opBg : type === 'io' ? palette.ioBg : type === 'focus' ? palette.focusBg : palette.componentBg;
          ctx.strokeStyle = type === 'focus' ? palette.focusBorder : type === 'io' ? palette.ioBorder : palette.componentBorder;
          ctx.lineWidth = type === 'focus' ? 2.2 : 1.7;
          const r = 6;
          ctx.beginPath();
          ctx.moveTo(sym.x - hw + r, sym.y - hh);
          ctx.lineTo(sym.x + hw - r, sym.y - hh);
          ctx.arcTo(sym.x + hw, sym.y - hh, sym.x + hw, sym.y - hh + r, r);
          ctx.lineTo(sym.x + hw, sym.y + hh - r);
          ctx.arcTo(sym.x + hw, sym.y + hh, sym.x + hw - r, sym.y + hh, r);
          ctx.lineTo(sym.x - hw + r, sym.y + hh);
          ctx.arcTo(sym.x - hw, sym.y + hh, sym.x - hw, sym.y + hh - r, r);
          ctx.lineTo(sym.x - hw, sym.y - hh + r);
          ctx.arcTo(sym.x - hw, sym.y - hh, sym.x - hw + r, sym.y - hh, r);
          ctx.closePath();
          ctx.fill();
          ctx.stroke();
          // Label
          ctx.fillStyle = palette.componentText;
          ctx.font = `${Math.max(8, Math.min(12, hw / 4))}px monospace`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(sym.label || '', sym.x, sym.y);
        }

        // Draw nets
        for (const net of renderList.nets) {
          const hw = (net.width || 52) / 2;
          const hh = (net.height || 18) / 2;
          ctx.fillStyle = net.active ? palette.wireActive : palette.netBg;
          ctx.strokeStyle = palette.netBorder;
          ctx.lineWidth = 1.2;
          ctx.beginPath();
          ctx.ellipse(net.x, net.y, hw, hh, 0, 0, Math.PI * 2);
          ctx.fill();
          ctx.stroke();
          ctx.fillStyle = palette.netText;
          ctx.font = '7px monospace';
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillText(net.label || '', net.x, net.y);
        }

        // Draw pins
        for (const pin of renderList.pins) {
          const hw = (pin.width || 12) / 2;
          const hh = (pin.height || 12) / 2;
          ctx.fillStyle = pin.active ? palette.wireActive : palette.pinBg;
          ctx.strokeStyle = palette.pinBorder;
          ctx.lineWidth = 1.0;
          ctx.beginPath();
          ctx.arc(pin.x, pin.y, Math.min(hw, hh), 0, Math.PI * 2);
          ctx.fill();
          ctx.stroke();
        }

        ctx.setTransform(1, 0, 0, 1, 0, 0);
        return offscreen.toDataURL('image/png');
      }, { focusId, showChildren, width, height, viewport });

      return dataUrl;
    }

    // Save a data URL to a file
    async function saveDataUrl(dataUrl, filename) {
      if (!dataUrl) { console.log(`  No data for ${filename}`); return; }
      const base64 = dataUrl.replace(/^data:image\/png;base64,/, '');
      await writeFile(path.join(screenshotDir, filename), Buffer.from(base64, 'base64'));
      console.log(`  Saved ${filename}`);
    }

    const modelInfo = await page.evaluate(() => {
      const state = window.__RHDL_UX_STATE__;
      const model = state?.components?.model;
      if (!model) return null;
      const rootNode = model.nodes.get(model.rootId);
      return {
        rootId: model.rootId,
        childIds: rootNode ? rootNode.children.map(c => c.id || c).slice(0, 10) : []
      };
    });
    console.log(`Model: root=${modelInfo?.rootId}, children=${modelInfo?.childIds?.length}`);

    const W = 1920;
    const H = 1080;

    // 1. Overview (auto-fit)
    let url = await captureSchematic({ focusId: modelInfo.rootId, showChildren: true, width: W, height: H, viewport: null, label: 'd3_schematic_overview' });
    await saveDataUrl(url, 'd3_schematic_overview.png');

    // 2. Zoomed in (2x)
    url = await captureSchematic({ focusId: modelInfo.rootId, showChildren: true, width: W, height: H, viewport: { scaleMul: 2.5 }, label: 'd3_schematic_zoomed_in' });
    await saveDataUrl(url, 'd3_schematic_zoomed_in.png');

    // 3. Panned (shifted)
    url = await captureSchematic({ focusId: modelInfo.rootId, showChildren: true, width: W, height: H, viewport: { scaleMul: 2, panX: 300, panY: 150 }, label: 'd3_schematic_panned' });
    await saveDataUrl(url, 'd3_schematic_panned.png');

    // 4. Zoomed out (0.6x)
    url = await captureSchematic({ focusId: modelInfo.rootId, showChildren: true, width: W, height: H, viewport: { scaleMul: 0.6 }, label: 'd3_schematic_zoomed_out' });
    await saveDataUrl(url, 'd3_schematic_zoomed_out.png');

    // 5. Drill down into a child component
    if (modelInfo.childIds.length > 0) {
      const childId = modelInfo.childIds[0];
      console.log(`Drilling into ${childId}...`);

      // Switch focus to child and rebuild the graph
      await page.evaluate(({ childId }) => {
        const state = window.__RHDL_UX_STATE__;
        if (state.components.graph && typeof state.components.graph.destroy === 'function') {
          state.components.graph.destroy();
        }
        state.components.graph = null;
        state.components.graphKey = '';
        state.components.selectedNodeId = childId;
        state.components.graphFocusId = childId;
        state.components.graphShowChildren = true;
      }, { childId });

      await page.click('[data-tab="componentTab"]');
      await page.waitForTimeout(500);
      await page.click('[data-tab="componentGraphTab"]');
      await page.waitForTimeout(4000);

      url = await captureSchematic({ focusId: childId, showChildren: true, width: W, height: H, viewport: null, label: 'd3_schematic_drilled_down' });
      await saveDataUrl(url, 'd3_schematic_drilled_down.png');
    }

    console.log('Done! Screenshots saved to docs/screenshots/');
  } finally {
    await browser.close();
    server.close();
  }
}

main().catch((err) => { console.error(err); process.exit(1); });
