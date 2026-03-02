import test from 'node:test';
import assert from 'node:assert/strict';
import { createWebGLRenderer } from '../../../../app/components/explorer/renderers/webgl_renderer';
import type { RenderList, RenderNet, RenderPin, RenderSymbol, RenderWire } from '../../../../app/components/explorer/lib/types';

type GlCall = { method: string; args: unknown[] };

function createMockCanvas(hasWebGL = true) {
  const glCalls: GlCall[] = [];
  const gl = hasWebGL ? new Proxy({}, {
    get(target: Record<PropertyKey, unknown>, prop: PropertyKey) {
      if (prop in target) return target[prop];
      if (prop === 'canvas') return { width: 800, height: 600 };
      if (prop === 'drawingBufferWidth') return 800;
      if (prop === 'drawingBufferHeight') return 600;
      // GL constants
      if (prop === 'VERTEX_SHADER') return 35633;
      if (prop === 'FRAGMENT_SHADER') return 35632;
      if (prop === 'LINK_STATUS') return 35714;
      if (prop === 'COMPILE_STATUS') return 35713;
      if (prop === 'ARRAY_BUFFER') return 34962;
      if (prop === 'STATIC_DRAW') return 35044;
      if (prop === 'DYNAMIC_DRAW') return 35048;
      if (prop === 'FLOAT') return 5126;
      if (prop === 'LINES') return 1;
      if (prop === 'TRIANGLES') return 4;
      if (prop === 'TRIANGLE_STRIP') return 5;
      if (prop === 'COLOR_BUFFER_BIT') return 16384;
      if (prop === 'BLEND') return 3042;
      if (prop === 'SRC_ALPHA') return 770;
      if (prop === 'ONE_MINUS_SRC_ALPHA') return 771;
      return (...args: unknown[]) => {
        glCalls.push({ method: String(prop), args });
        // Return sensible defaults for GL queries
        if (prop === 'createShader') return {};
        if (prop === 'createProgram') return {};
        if (prop === 'createBuffer') return {};
        if (prop === 'getShaderParameter') return true;
        if (prop === 'getProgramParameter') return true;
        if (prop === 'getAttribLocation') return glCalls.filter(c => c.method === 'getAttribLocation').length - 1;
        if (prop === 'getUniformLocation') return {};
        return undefined;
      };
    }
  }) : null;

  return {
    canvas: {
      width: 800,
      height: 600,
      style: {},
      getContext(type: string) {
        if (type === 'webgl2') return gl;
        return null;
      },
      addEventListener() {},
      removeEventListener() {}
    },
    gl,
    glCalls
  };
}

function makePalette() {
  return {
    componentBg: '#1b3d32', componentBorder: '#76d4a4', componentText: '#d8eee0',
    pinBg: '#2d5d4f', pinBorder: '#8bd7b5',
    netBg: '#243a35', netBorder: '#527a6d', netText: '#b6d2c5',
    ioBg: '#28463d', ioBorder: '#7ecdad',
    opBg: '#3f4c3a', memoryBg: '#4f3e2f',
    wire: '#4f7d6d', wireActive: '#7be9ad', wireToggle: '#f4bf66', selected: '#9cffe3'
  };
}

function makeRenderList(count = 2) {
  const symbols: RenderSymbol[] = [];
  const pins: RenderPin[] = [];
  const nets: RenderNet[] = [];
  const wires: RenderWire[] = [];
  const byId = new Map<string, unknown>();
  for (let i = 0; i < count; i++) {
    const sym = {
      id: `s${i}`, type: 'component', label: `C${i}`,
      x: i * 200, y: 100, width: 178, height: 72,
      active: false, toggled: false, selected: false
    };
    symbols.push(sym);
    byId.set(sym.id, sym);

    const pin = {
      id: `p${i}`, symbolId: `s${i}`, x: i * 200, y: 80, width: 14, height: 10,
      bus: false, active: false, toggled: false, selected: false
    };
    pins.push(pin);
    byId.set(pin.id, pin);

    const net = {
      id: `n${i}`, label: `net${i}`, x: i * 200 + 100, y: 100, width: 52, height: 18,
      bus: false, active: false, toggled: false, selected: false
    };
    nets.push(net);
    byId.set(net.id, net);

    if (i > 0) {
      const wire = {
        id: `w${i}`, sourceId: `p${i - 1}`, targetId: `n${i}`,
        bus: false, bidir: false, active: false, toggled: false, selected: false
      };
      wires.push(wire);
      byId.set(wire.id, wire);
    }
  }
  return { symbols, pins, nets, wires, byId } as RenderList;
}

function readFirstLineWidth(glCalls: GlCall[]) {
  const lineBufferUpload = glCalls.find((call) => (
    call.method === 'bufferData'
    && call.args?.[1] instanceof Float32Array
    && call.args[1].length >= 10
  ));
  if (!lineBufferUpload) {
    return 0;
  }
  const data = lineBufferUpload.args[1];
  if (!(data instanceof Float32Array)) {
    return 0;
  }
  return Number(data[8] || 0);
}

test('createWebGLRenderer returns object with render and destroy when WebGL2 available', () => {
  const { canvas } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas);
  assert.ok(renderer, 'renderer should not be null');
  assert.equal(typeof renderer.render, 'function');
  assert.equal(typeof renderer.destroy, 'function');
});

test('createWebGLRenderer returns null when WebGL2 unavailable', () => {
  const { canvas } = createMockCanvas(false);
  const renderer = createWebGLRenderer(canvas);
  assert.equal(renderer, null);
});

test('render calls GL functions (clear, bindBuffer, drawArrays/drawElements)', () => {
  const { canvas, glCalls } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas)!;
  const rl = makeRenderList(2);
  const viewport = { x: 0, y: 0, scale: 1 };

  renderer.render(rl, viewport, makePalette());

  assert.ok(glCalls.some(c => c.method === 'clear'), 'should call gl.clear');
  assert.ok(glCalls.some(c => c.method === 'useProgram'), 'should call gl.useProgram');
});

test('render resets line attribute divisors before drawing wires', () => {
  const { canvas, glCalls } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas)!;
  const rl = makeRenderList(3);
  const viewport = { x: 0, y: 0, scale: 1 };

  renderer.render(rl, viewport, makePalette());

  const firstLineDraw = glCalls.findIndex((call) => call.method === 'drawArrays' && call.args[0] === 5);
  assert.ok(firstLineDraw >= 0, 'wire pass should issue TRIANGLE_STRIP draws');

  for (const location of [0, 1, 2, 3, 4]) {
    const divisorCall = glCalls.findIndex((call) => (
      call.method === 'vertexAttribDivisor' &&
      call.args[0] === location &&
      call.args[1] === 0
    ));
    assert.ok(divisorCall >= 0, `line attribute ${location} should reset divisor to 0`);
    assert.ok(divisorCall < firstLineDraw, `line attribute ${location} divisor reset must happen before drawing wires`);
  }
});

test('render attenuates wire widths while zoomed out', () => {
  const { canvas, glCalls } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas)!;
  const rl = makeRenderList(2);

  glCalls.length = 0;
  renderer.render(rl, { x: 0, y: 0, scale: 1 }, makePalette());
  const fullScaleWidth = readFirstLineWidth(glCalls);

  glCalls.length = 0;
  renderer.render(rl, { x: 0, y: 0, scale: 0.1 }, makePalette());
  const zoomedOutWidth = readFirstLineWidth(glCalls);

  assert.ok(fullScaleWidth > 0, 'wire width should be populated at full scale');
  assert.ok(zoomedOutWidth > 0, 'wire width should be populated while zoomed out');
  assert.ok(zoomedOutWidth < fullScaleWidth, 'wire width should shrink while zoomed out');
});

test('destroy does not throw', () => {
  const { canvas } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas)!;
  renderer.destroy();
});

test('render with empty renderList does not throw', () => {
  const { canvas } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas)!;
  const rl: RenderList = {
    symbols: [],
    pins: [],
    nets: [],
    wires: [],
    byId: new Map<string, unknown>()
  };
  renderer.render(rl, { x: 0, y: 0, scale: 1 }, makePalette());
});

test('render with large renderList completes without error', () => {
  const { canvas } = createMockCanvas(true);
  const renderer = createWebGLRenderer(canvas)!;
  const rl = makeRenderList(500);
  const viewport = { x: 0, y: 0, scale: 1 };

  const start = performance.now();
  renderer.render(rl, viewport, makePalette());
  const elapsed = performance.now() - start;

  // Should complete in reasonable time (not a strict perf test in mocked GL)
  assert.ok(elapsed < 1000, `render of 500 symbols took ${elapsed}ms`);
});
