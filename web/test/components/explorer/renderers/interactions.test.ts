import test from 'node:test';
import assert from 'node:assert/strict';
import { bindD3Interactions } from '../../../../app/components/explorer/renderers/interactions';

type HighlightSignal = { signalName: string | null; liveName: string | null } | null;
type MockCanvasEvent = {
  clientX: number;
  clientY: number;
  button: number;
  deltaY: number;
  preventDefault: () => void;
  stopPropagation: () => void;
};
type MockCanvasListener = (event: MockCanvasEvent) => void;

// Minimal mock spatial index
function createMockIndex(hitMap: Map<string, unknown>) {
  return {
    queryPoint(x: number, y: number) {
      const key = `${x},${y}`;
      return hitMap.get(key) || null;
    }
  };
}

function createState() {
  return {
    components: {
      selectedNodeId: null as string | null,
      graphLastTap: null,
      graphFocusId: null as string | null,
      graphShowChildren: false,
      graphHighlightedSignal: null as HighlightSignal
    }
  };
}

// Mock canvas with event listener support
function createMockCanvas() {
  const listeners = new Map<string, MockCanvasListener[]>();
  return {
    width: 800,
    height: 600,
    listeners,
    addEventListener(event: string, handler: MockCanvasListener) {
      if (!listeners.has(event)) listeners.set(event, []);
      listeners.get(event)?.push(handler);
    },
    removeEventListener(event: string, handler: MockCanvasListener) {
      const list = listeners.get(event);
      if (list) {
        const idx = list.indexOf(handler);
        if (idx >= 0) list.splice(idx, 1);
      }
    },
    getBoundingClientRect() {
      return { left: 0, top: 0, width: 800, height: 600 };
    },
    emit(event: string, x: number, y: number, extra: Partial<MockCanvasEvent> = {}) {
      const handlers = listeners.get(event) || [];
      for (const h of handlers) {
        h({
          clientX: x,
          clientY: y,
          button: 0,
          deltaY: 0,
          preventDefault() {},
          stopPropagation() {},
          ...extra
        });
      }
    }
  };
}

test('bindD3Interactions returns object with destroy', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };
  const result = bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map()),
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    requestRender: () => {}
  });
  assert.equal(typeof result.destroy, 'function');
});

test('clicking a component symbol sets selectedNodeId', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map([['cpu', {}]]) };
  let treeRenders = 0;
  let viewRenders = 0;

  const component = {
    id: 'sym:cpu', type: 'component', componentId: 'cpu',
    x: 100, y: 100, width: 178, height: 72
  };

  bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map([['100,100', component]])),
    renderComponentTree: () => { treeRenders++; },
    renderComponentViews: () => { viewRenders++; },
    requestRender: () => {}
  });

  canvas.emit('click', 100, 100);
  assert.equal(state.components.selectedNodeId, 'cpu');
  assert.equal(treeRenders, 1);
  assert.equal(viewRenders, 1);
});

test('double-clicking a component sets graphFocusId and graphShowChildren', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map([['cpu', {}]]) };
  const timestamps = [1000, 1200];
  let viewRenders = 0;

  const component = {
    id: 'sym:cpu', type: 'component', componentId: 'cpu',
    x: 100, y: 100, width: 178, height: 72
  };

  bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map([['100,100', component]])),
    renderComponentTree: () => {},
    renderComponentViews: () => { viewRenders++; },
    requestRender: () => {},
    now: () => timestamps.shift() || 1500
  });

  canvas.emit('click', 100, 100); // first click
  assert.equal(state.components.graphFocusId, null);

  canvas.emit('click', 100, 100); // second click within 320ms
  assert.equal(state.components.graphFocusId, 'cpu');
  assert.equal(state.components.graphShowChildren, true);
  assert.equal(state.components.graphHighlightedSignal, null);
  assert.equal(viewRenders, 2);
});

test('clicking a net sets graphHighlightedSignal', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };
  let viewRenders = 0;

  const net = {
    id: 'net:clk', type: undefined, signalName: 'clk', liveName: 'top__clk',
    x: 200, y: 200, width: 52, height: 18
  };

  bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map([['200,200', net]])),
    renderComponentTree: () => {},
    renderComponentViews: () => { viewRenders++; },
    requestRender: () => {}
  });

  canvas.emit('click', 200, 200);
  assert.deepEqual(state.components.graphHighlightedSignal, { signalName: 'clk', liveName: 'top__clk' });
  assert.equal(viewRenders, 1);
});

test('clicking a pin sets graphHighlightedSignal', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };

  const pin = {
    id: 'pin:clk', signalName: 'clk', liveName: 'top__clk',
    x: 50, y: 50, width: 14, height: 10, symbolId: 'sym:cpu'
  };

  bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map([['50,50', pin]])),
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    requestRender: () => {}
  });

  canvas.emit('click', 50, 50);
  assert.deepEqual(state.components.graphHighlightedSignal, { signalName: 'clk', liveName: 'top__clk' });
});

test('clicking empty canvas clears graphHighlightedSignal', () => {
  const canvas = createMockCanvas();
  const state = createState();
  state.components.graphHighlightedSignal = { signalName: 'clk', liveName: 'top__clk' };
  const model = { nodes: new Map() };
  let viewRenders = 0;

  bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map()),
    renderComponentTree: () => {},
    renderComponentViews: () => { viewRenders++; },
    requestRender: () => {}
  });

  canvas.emit('click', 999, 999);
  assert.equal(state.components.graphHighlightedSignal, null);
  assert.equal(viewRenders, 1);
});

test('click hit-testing respects viewport transform', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };
  const viewport = { x: 50, y: 20, scale: 2 };
  const net = { id: 'net:clk', signalName: 'clk', liveName: 'top__clk' };

  bindD3Interactions({
    canvas,
    state,
    model,
    viewport,
    spatialIndex: createMockIndex(new Map([['20,20', net]])),
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    requestRender: () => {}
  });

  // screen (90,60) -> world ((90-50)/2, (60-20)/2) = (20,20)
  canvas.emit('click', 90, 60);
  assert.deepEqual(state.components.graphHighlightedSignal, { signalName: 'clk', liveName: 'top__clk' });
});

test('wheel zoom updates viewport scale and requests render', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };
  const viewport = { x: 0, y: 0, scale: 1 };
  let renders = 0;

  bindD3Interactions({
    canvas,
    state,
    model,
    viewport,
    spatialIndex: createMockIndex(new Map()),
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    requestRender: () => { renders++; }
  });

  canvas.emit('wheel', 400, 300, { deltaY: -120 });
  assert.ok(viewport.scale > 1, 'zoom-in should increase scale');
  assert.ok(viewport.x < 0, 'zoom-in should update x translation');
  assert.ok(viewport.y < 0, 'zoom-in should update y translation');
  assert.equal(renders, 1);
});

test('wheel zoom clamps to extended minimum scale when zooming far out', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };
  const viewport = { x: 0, y: 0, scale: 1 };

  bindD3Interactions({
    canvas,
    state,
    model,
    viewport,
    spatialIndex: createMockIndex(new Map()),
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    requestRender: () => {}
  });

  canvas.emit('wheel', 400, 300, { deltaY: 100000 });
  assert.ok(viewport.scale <= 0.051, 'zoom-out should clamp at extended minimum scale');
  assert.ok(viewport.scale >= 0.05, 'zoom-out should not go below minimum scale');
});

test('drag pan updates viewport translation and suppresses click selection', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map([['cpu', {}]]) };
  const viewport = { x: 0, y: 0, scale: 1 };
  let renders = 0;
  let viewRenders = 0;
  const component = { id: 'sym:cpu', type: 'component', componentId: 'cpu' };

  bindD3Interactions({
    canvas,
    state,
    model,
    viewport,
    spatialIndex: createMockIndex(new Map([['110,110', component]])),
    renderComponentTree: () => {},
    renderComponentViews: () => { viewRenders++; },
    requestRender: () => { renders++; }
  });

  canvas.emit('mousedown', 100, 100);
  canvas.emit('mousemove', 140, 130);
  canvas.emit('mouseup', 140, 130);
  assert.equal(viewport.x, 40);
  assert.equal(viewport.y, 30);
  assert.ok(renders > 0, 'panning should render');

  // Click from the drag-release should be ignored.
  canvas.emit('click', 110, 110);
  assert.equal(state.components.selectedNodeId, null);
  assert.equal(viewRenders, 0);
});

test('destroy removes click listener', () => {
  const canvas = createMockCanvas();
  const state = createState();
  const model = { nodes: new Map() };

  const handle = bindD3Interactions({
    canvas,
    state,
    model,
    spatialIndex: createMockIndex(new Map()),
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    requestRender: () => {}
  });

  const before = (canvas.listeners.get('click') || []).length;
  handle.destroy();
  const after = (canvas.listeners.get('click') || []).length;
  assert.ok(after < before, 'click listener should be removed');
});
