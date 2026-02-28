import test from 'node:test';
import assert from 'node:assert/strict';
import { createCanvasRenderer } from '../../../../app/components/explorer/renderers/canvas_renderer';

function createMockCanvas() {
  const calls = [];
  const ctxHandler = {
    get(target, prop) {
      if (prop in target) return target[prop];
      if (prop === 'canvas') return target._canvas;
      if (prop === 'measureText') {
        return (text = '') => ({ width: String(text).length * 6 });
      }
      return (...args) => { calls.push({ method: prop, args }); };
    },
    set(target, prop, value) {
      calls.push({ method: `set:${String(prop)}`, args: [value] });
      target[prop] = value;
      return true;
    }
  };
  const ctx = new Proxy({ calls, _canvas: null }, ctxHandler);
  const canvas = {
    width: 800,
    height: 600,
    getContext(type) {
      if (type === '2d') {
        ctx._canvas = canvas;
        return ctx;
      }
      return null;
    },
    getBoundingClientRect() {
      return { left: 0, top: 0, width: 800, height: 600 };
    }
  };
  return { canvas, ctx, calls };
}

function createMockPalette() {
  return {
    componentBg: '#1b3d32',
    componentBorder: '#76d4a4',
    componentText: '#d8eee0',
    pinBg: '#2d5d4f',
    pinBorder: '#8bd7b5',
    netBg: '#243a35',
    netBorder: '#527a6d',
    netText: '#b6d2c5',
    ioBg: '#28463d',
    ioBorder: '#7ecdad',
    opBg: '#3f4c3a',
    memoryBg: '#4f3e2f',
    wire: '#4f7d6d',
    wireActive: '#7be9ad',
    wireToggle: '#f4bf66',
    selected: '#9cffe3'
  };
}

function minimalRenderList() {
  return {
    symbols: [
      { id: 'sym:cpu', label: 'CPU', type: 'focus', x: 200, y: 100, width: 228, height: 94, componentId: 'cpu', classes: '' },
      { id: 'sym:alu', label: 'ALU', type: 'component', x: 500, y: 100, width: 178, height: 72, componentId: 'alu', classes: '' }
    ],
    pins: [
      { id: 'pin:clk', label: 'clk', x: 86, y: 80, width: 14, height: 10, symbolId: 'sym:cpu', side: 'left', bus: false, classes: '' }
    ],
    nets: [
      { id: 'net:clk', label: 'clk', x: 350, y: 100, width: 52, height: 18, bus: false, classes: '', active: false, toggled: false, selected: false }
    ],
    wires: [
      { id: 'w1', sourceId: 'pin:clk', targetId: 'net:clk', bus: false, bidir: false, classes: '', active: false, toggled: false, selected: false }
    ],
    byId: new Map()
  };
  // wire up byId
}

test('createCanvasRenderer returns object with render and destroy', () => {
  const { canvas } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  assert.equal(typeof renderer.render, 'function');
  assert.equal(typeof renderer.destroy, 'function');
});

test('render clears canvas and draws elements', () => {
  const { canvas, calls } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  const rl = minimalRenderList();
  const viewport = { x: 0, y: 0, scale: 1 };

  renderer.render(rl, viewport, createMockPalette());

  assert.ok(calls.some(c => c.method === 'clearRect'), 'should clear canvas');
  assert.ok(calls.some(c => c.method === 'beginPath'), 'should draw shapes');
});

test('render with empty renderList clears but does not throw', () => {
  const { canvas, calls } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  const rl = { symbols: [], pins: [], nets: [], wires: [], byId: new Map() };
  const viewport = { x: 0, y: 0, scale: 1 };

  renderer.render(rl, viewport, createMockPalette());

  assert.ok(calls.some(c => c.method === 'clearRect'), 'should still clear');
});

test('render applies viewport transform via setTransform', () => {
  const { canvas, calls } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  const rl = minimalRenderList();
  const viewport = { x: 50, y: 30, scale: 2.0 };

  renderer.render(rl, viewport, createMockPalette());

  const setTransformCall = calls.find(c => c.method === 'setTransform');
  assert.ok(setTransformCall, 'should call setTransform for viewport');
  assert.equal(setTransformCall.args[0], 2.0, 'scale x');
  assert.equal(setTransformCall.args[3], 2.0, 'scale y');
  assert.equal(setTransformCall.args[4], 50, 'translate x');
  assert.equal(setTransformCall.args[5], 30, 'translate y');
});

test('render draws wires as line segments', () => {
  const { canvas, calls } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  const rl = minimalRenderList();
  // populate byId so wire endpoints can be resolved
  for (const s of rl.symbols) rl.byId.set(s.id, s);
  for (const p of rl.pins) rl.byId.set(p.id, p);
  for (const n of rl.nets) rl.byId.set(n.id, n);
  const viewport = { x: 0, y: 0, scale: 1 };

  renderer.render(rl, viewport, createMockPalette());

  assert.ok(calls.some(c => c.method === 'moveTo'), 'should draw wire with moveTo');
  assert.ok(calls.some(c => c.method === 'lineTo'), 'should draw wire with lineTo');
});

test('render thins wire widths as viewport scale decreases', () => {
  const { canvas, calls } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  const rl = minimalRenderList();
  for (const s of rl.symbols) rl.byId.set(s.id, s);
  for (const p of rl.pins) rl.byId.set(p.id, p);
  for (const n of rl.nets) rl.byId.set(n.id, n);

  calls.length = 0;
  renderer.render(rl, { x: 0, y: 0, scale: 1 }, createMockPalette());
  const fullScaleWidth = calls.find((c) => c.method === 'set:lineWidth')?.args?.[0] || 0;

  calls.length = 0;
  renderer.render(rl, { x: 0, y: 0, scale: 0.1 }, createMockPalette());
  const zoomedOutWidth = calls.find((c) => c.method === 'set:lineWidth')?.args?.[0] || 0;

  assert.ok(fullScaleWidth > 0, 'wire width should be set at full scale');
  assert.ok(zoomedOutWidth > 0, 'wire width should be set while zoomed out');
  assert.ok(zoomedOutWidth < fullScaleWidth, 'wire width should shrink while zoomed out');
});

test('render draws wires as polylines when bendPoints are present', () => {
  const { canvas, calls } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  const rl = {
    symbols: [],
    pins: [
      { id: 'pin:a', x: 100, y: 50, width: 14, height: 10, bus: false, classes: '' },
      { id: 'pin:b', x: 400, y: 200, width: 14, height: 10, bus: false, classes: '' }
    ],
    nets: [],
    wires: [
      {
        id: 'w1', sourceId: 'pin:a', targetId: 'pin:b',
        bus: false, bidir: false, classes: '',
        active: false, toggled: false, selected: false,
        bendPoints: [
          { x: 100, y: 50 },
          { x: 250, y: 50 },
          { x: 250, y: 200 },
          { x: 400, y: 200 }
        ]
      }
    ],
    byId: new Map()
  };
  for (const p of rl.pins) rl.byId.set(p.id, p);
  for (const w of rl.wires) rl.byId.set(w.id, w);
  const viewport = { x: 0, y: 0, scale: 1 };

  renderer.render(rl, viewport, createMockPalette());

  // Should have moveTo for start and multiple lineTo for each bend
  const moveToIdx = calls.findIndex(c => c.method === 'moveTo');
  assert.ok(moveToIdx >= 0, 'should call moveTo');
  // Count lineTo calls after the first moveTo for this wire
  const lineToCount = calls.filter((c, i) => i > moveToIdx && c.method === 'lineTo').length;
  assert.ok(lineToCount >= 3, `should have at least 3 lineTo calls for 4-point polyline, got ${lineToCount}`);
});

test('destroy does not throw', () => {
  const { canvas } = createMockCanvas();
  const renderer = createCanvasRenderer(canvas);
  renderer.destroy();
});
