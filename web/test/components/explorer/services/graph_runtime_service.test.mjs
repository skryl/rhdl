import test from 'node:test';
import assert from 'node:assert/strict';
import { createExplorerGraphRuntimeService } from '../../../../app/components/explorer/services/graph_runtime_service.mjs';

function createService(overrides = {}) {
  return createExplorerGraphRuntimeService({
    dom: { componentVisual: null },
    state: {
      theme: 'default',
      activeTab: 'componentGraphTab',
      components: {
        graph: null,
        graphKey: '',
        graphSelectedId: null,
        graphLastTap: null,
        graphLayoutEngine: 'none',
        graphElkAvailable: false,
        graphShowChildren: true,
        parseError: '',
        sourceKey: 'k',
        model: null
      }
    },
    currentComponentGraphFocusNode: () => null,
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    createSchematicElements: () => [],
    signalLiveValueByName: () => null,
    ...overrides
  });
}

function buildGraphKey({ sourceKey = 'k', theme = 'default', focusNode, showChildren = true, elkAvailable = true } = {}) {
  return `${sourceKey}:d3:${theme}:none:${focusNode.id}:${showChildren ? 1 : 0}:${focusNode.children.length}:${focusNode.signals.length}:${elkAvailable ? 1 : 0}`;
}

test('explorer graph runtime service resets graph runtime state on destroy', () => {
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: {
        destroyed: false,
        destroy() {
          this.destroyed = true;
        }
      },
      graphKey: 'k',
      graphSelectedId: 'id',
      graphLastTap: { nodeId: 'n', timeMs: 0 },
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      parseError: '',
      sourceKey: 'k',
      model: null
    }
  };
  const service = createService({ state });
  const graphRef = state.components.graph;

  service.destroyComponentGraph();

  assert.equal(graphRef.destroyed, true);
  assert.equal(state.components.graph, null);
  assert.equal(state.components.graphKey, '');
  assert.equal(state.components.graphSelectedId, null);
  assert.equal(state.components.graphLastTap, null);
  assert.equal(state.components.graphLayoutEngine, 'none');
  assert.equal(state.components.graphElkAvailable, false);
});

test('explorer graph runtime service builds panel metadata', () => {
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: null,
      graphKey: '',
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      parseError: '',
      sourceKey: 'k',
      model: { rootId: 'top' }
    }
  };
  const service = createService({ state });

  const selected = { id: 'cpu', path: 'top.cpu' };
  const focus = { id: 'cpu', path: 'top.cpu', parentId: 'top' };
  const panel = service.describeComponentGraphPanel({ selectedNode: selected, focusNode: focus });
  assert.match(panel.meta, /layout=elk/);
  assert.equal(panel.topDisabled, false);
  assert.equal(panel.upDisabled, false);
});

test('explorer graph runtime service validates required callbacks', () => {
  assert.throws(
    () => createService({ renderComponentTree: null }),
    /requires function: renderComponentTree/
  );
});

test('renderComponentVisual builds schematic graph asynchronously and reports loading state first', async (t) => {
  const previousWindow = globalThis.window;
  const previousDocument = globalThis.document;
  const listeners = new Map();

  function createCanvas() {
    return {
      width: 0,
      height: 0,
      style: {},
      getContext(kind) {
        if (kind === '2d') {
          return null;
        }
        return null;
      },
      addEventListener(type, handler) {
        listeners.set(type, handler);
      },
      removeEventListener(type, handler) {
        const current = listeners.get(type);
        if (current === handler) {
          listeners.delete(type);
        }
      },
      getBoundingClientRect() {
        return { width: 900, height: 700, left: 0, top: 0 };
      }
    };
  }

  globalThis.window = {
    ...(previousWindow || {}),
    ELK: class ELK {
      layout() {
        return Promise.resolve({ children: [], edges: [] });
      }
    },
    addEventListener() {},
    removeEventListener() {}
  };
  globalThis.document = {
    createElement(tag) {
      if (tag === 'canvas') {
        return createCanvas();
      }
      return { style: {}, appendChild() {} };
    }
  };
  t.after(() => {
    globalThis.window = previousWindow;
    globalThis.document = previousDocument;
  });

  let createCalls = 0;
  let rerenderCalls = 0;
  const focusNode = { id: 'cpu', path: 'top.cpu', parentId: 'top', children: [], signals: [] };
  const model = {
    rootId: 'top',
    nodes: new Map([
      ['cpu', focusNode]
    ])
  };
  const componentVisual = {
    innerHTML: '',
    textContent: '',
    style: {},
    clientWidth: 900,
    clientHeight: 700,
    appendChild() {}
  };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: null,
      graphKey: '',
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'none',
      graphElkAvailable: false,
      graphShowChildren: true,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model
    }
  };
  const service = createService({
    dom: { componentVisual },
    state,
    currentComponentGraphFocusNode: () => focusNode,
    createSchematicElements: () => {
      createCalls += 1;
      return [];
    }
  });

  const first = service.renderComponentVisual({
    node: focusNode,
    model,
    rerender: () => {
      rerenderCalls += 1;
    }
  });

  assert.equal(first.ok, false);
  assert.equal(first.reason, 'graph-loading');
  assert.equal(createCalls, 0, 'graph build should be deferred to async task');
  assert.equal(componentVisual.textContent, 'Loading schematic...');

  for (let i = 0; i < 8 && !state.components.graph; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }

  assert.ok(state.components.graph, 'graph handle should be installed after async build');
  assert.ok(createCalls > 0, 'schematic elements should be built asynchronously');
  assert.ok(rerenderCalls > 0, 'graph completion should trigger rerender');
});

// --- d3 renderer tests ---

test('destroyComponentGraph cleans up d3 renderer handle', () => {
  let rendererDestroyed = false;
  let interactionsDestroyed = false;
  const state = {
    theme: 'shenzhen',
    activeTab: 'componentGraphTab',
    components: {
      graph: {
        type: 'd3',
        renderer: { destroy() { rendererDestroyed = true; }, render() {} },
        interactions: { destroy() { interactionsDestroyed = true; } },
        destroy() {
          this.renderer.destroy();
          this.interactions.destroy();
        }
      },
      graphKey: 'k',
      graphSelectedId: 'id',
      graphLastTap: { nodeId: 'n', timeMs: 0 },
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model: null
    }
  };
  const service = createService({ state });
  service.destroyComponentGraph();

  assert.equal(state.components.graph, null);
  assert.equal(state.components.graphKey, '');
  assert.equal(rendererDestroyed, true);
  assert.equal(interactionsDestroyed, true);
});

test('describeComponentGraphPanel shows renderer info', () => {
  const state = {
    theme: 'shenzhen',
    activeTab: 'componentGraphTab',
    components: {
      graph: null,
      graphKey: '',
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphRenderBackend: 'canvas2d',
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model: { rootId: 'top' }
    }
  };
  const service = createService({ state });
  const panel = service.describeComponentGraphPanel({
    selectedNode: { id: 'cpu', path: 'top.cpu' },
    focusNode: { id: 'cpu', path: 'top.cpu', parentId: 'top' }
  });
  assert.match(panel.meta, /layout=elk/);
});

test('explorer graph runtime service zoom buttons adjust viewport and rerender', () => {
  let renders = 0;
  let legends = 0;
  const viewport = { x: 0, y: 0, scale: 1 };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: {
        renderer: {
          render() {
            renders += 1;
          }
        },
        canvas: {
          width: 800,
          height: 600,
          getBoundingClientRect() {
            return { width: 800, height: 600 };
          }
        },
        viewport,
        renderList: [],
        renderLegendOverlay() {
          legends += 1;
        }
      },
      graphKey: '',
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model: null
    }
  };
  const service = createService({ state });

  service.zoomInComponentGraph();
  assert.ok(viewport.scale > 1);
  assert.ok(renders > 0);
  assert.ok(legends > 0);

  const beforeOut = viewport.scale;
  service.zoomOutComponentGraph();
  assert.ok(viewport.scale < beforeOut);
});

test('explorer graph runtime service zoom-out button reaches extended minimum scale', () => {
  const viewport = { x: 0, y: 0, scale: 1 };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: {
        renderer: { render() {} },
        canvas: {
          width: 800,
          height: 600,
          getBoundingClientRect() {
            return { width: 800, height: 600 };
          }
        },
        viewport,
        renderList: []
      },
      graphKey: '',
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model: null
    }
  };
  const service = createService({ state });

  for (let i = 0; i < 40; i += 1) {
    service.zoomOutComponentGraph();
  }

  assert.ok(viewport.scale < 0.2, 'zoom-out floor should allow smaller scales than previous minimum');
  assert.ok(viewport.scale >= 0.05, 'zoom-out floor should clamp at extended minimum');
  assert.ok(viewport.scale <= 0.051, 'zoom-out floor should stay near extended minimum');
});

test('explorer graph runtime service reset viewport restores defaults and rerenders', () => {
  let renders = 0;
  let legends = 0;
  const viewport = { x: 140, y: -60, scale: 2.25 };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: {
        renderer: {
          render() {
            renders += 1;
          }
        },
        canvas: {
          width: 800,
          height: 600,
          getBoundingClientRect() {
            return { width: 800, height: 600 };
          }
        },
        viewport,
        renderList: [],
        renderLegendOverlay() {
          legends += 1;
        }
      },
      graphKey: '',
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model: null
    }
  };
  const service = createService({ state });

  const reset = service.resetComponentGraphViewport();

  assert.equal(reset, true);
  assert.equal(viewport.x, 0);
  assert.equal(viewport.y, 0);
  assert.equal(viewport.scale, 1);
  assert.ok(renders > 0);
  assert.ok(legends > 0);
});

test('renderComponentVisual keeps schematic activity static when trace is disabled', (t) => {
  const previousWindow = globalThis.window;
  globalThis.window = {
    ...(previousWindow || {}),
    ELK: class ELK {}
  };
  t.after(() => {
    globalThis.window = previousWindow;
  });

  let liveValueReads = 0;
  const signalName = 'top.cpu.sig';
  const focusNode = { id: 'cpu', path: 'top.cpu', parentId: 'top', children: [], signals: [] };
  const model = { rootId: 'top' };
  const net = { valueKey: 'sig_key', liveName: signalName, signalName: 'sig', active: true, toggled: true };
  const wire = { valueKey: 'sig_key', liveName: signalName, signalName: 'sig', active: true, toggled: true };
  const graph = {
    renderer: { render() {} },
    renderList: { nets: [net], pins: [], wires: [wire] },
    viewport: { x: 0, y: 0, scale: 1 }
  };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph,
      graphKey: buildGraphKey({ focusNode }),
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphHighlightedSignal: { liveName: signalName },
      graphLiveValues: new Map([['sig_key', '99']]),
      parseError: '',
      sourceKey: 'k',
      model
    }
  };
  const service = createService({
    dom: {
      componentVisual: {
        innerHTML: '',
        textContent: '',
        clientWidth: 900,
        clientHeight: 700
      }
    },
    state,
    currentComponentGraphFocusNode: () => focusNode,
    signalLiveValueByName: () => {
      liveValueReads += 1;
      return 123;
    },
    isTraceEnabled: () => false
  });

  const result = service.renderComponentVisual({
    node: focusNode,
    model,
    rerender: () => {}
  });

  assert.equal(result.ok, true);
  assert.equal(liveValueReads, 0);
  assert.equal(net.active, false);
  assert.equal(net.toggled, false);
  assert.equal(net.selected, true);
  assert.equal(wire.active, false);
  assert.equal(wire.toggled, false);
  assert.equal(wire.selected, true);
  assert.equal(state.components.graphLiveValues.get('sig_key'), '');
});

test('renderComponentVisual animates schematic activity when trace is enabled', (t) => {
  const previousWindow = globalThis.window;
  globalThis.window = {
    ...(previousWindow || {}),
    ELK: class ELK {}
  };
  t.after(() => {
    globalThis.window = previousWindow;
  });

  let liveValue = 1;
  const signalName = 'top.cpu.sig';
  const focusNode = { id: 'cpu', path: 'top.cpu', parentId: 'top', children: [], signals: [] };
  const model = { rootId: 'top' };
  const net = { valueKey: 'sig_key', liveName: signalName, signalName: 'sig' };
  const wire = { valueKey: 'sig_key', liveName: signalName, signalName: 'sig' };
  const graph = {
    renderer: { render() {} },
    renderList: { nets: [net], pins: [], wires: [wire] },
    viewport: { x: 0, y: 0, scale: 1 }
  };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph,
      graphKey: buildGraphKey({ focusNode }),
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphHighlightedSignal: null,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model
    }
  };
  const service = createService({
    dom: {
      componentVisual: {
        innerHTML: '',
        textContent: '',
        clientWidth: 900,
        clientHeight: 700
      }
    },
    state,
    currentComponentGraphFocusNode: () => focusNode,
    signalLiveValueByName: () => liveValue,
    isTraceEnabled: () => true
  });

  const first = service.renderComponentVisual({
    node: focusNode,
    model,
    rerender: () => {}
  });
  assert.equal(first.ok, true);
  assert.equal(net.active, true);
  assert.equal(net.toggled, false);
  assert.equal(wire.active, true);
  assert.equal(wire.toggled, false);

  liveValue = 2;
  const second = service.renderComponentVisual({
    node: focusNode,
    model,
    rerender: () => {}
  });
  assert.equal(second.ok, true);
  assert.equal(net.toggled, true);
  assert.equal(wire.toggled, true);
});

test('renderComponentVisual resizes schematic canvas backing store to match viewport size', (t) => {
  const previousWindow = globalThis.window;
  globalThis.window = {
    ...(previousWindow || {}),
    ELK: class ELK {}
  };
  t.after(() => {
    globalThis.window = previousWindow;
  });

  let renders = 0;
  const focusNode = { id: 'cpu', path: 'top.cpu', parentId: 'top', children: [], signals: [] };
  const model = { rootId: 'top' };
  const canvas = {
    width: 640,
    height: 360,
    getBoundingClientRect() {
      return { width: 1280, height: 720 };
    }
  };
  const legendCanvas = {
    width: 640,
    height: 360
  };
  const state = {
    theme: 'default',
    activeTab: 'componentGraphTab',
    components: {
      graph: {
        renderer: {
          render() {
            renders += 1;
          }
        },
        canvas,
        legendCanvas,
        viewport: { x: 0, y: 0, scale: 1 },
        renderList: { symbols: [], pins: [], nets: [], wires: [], byId: new Map() }
      },
      graphKey: buildGraphKey({ focusNode }),
      graphSelectedId: null,
      graphLastTap: null,
      graphLayoutEngine: 'elk',
      graphElkAvailable: true,
      graphShowChildren: true,
      graphHighlightedSignal: null,
      graphLiveValues: new Map(),
      parseError: '',
      sourceKey: 'k',
      model
    }
  };
  const service = createService({
    dom: {
      componentVisual: {
        innerHTML: '',
        textContent: '',
        clientWidth: 1280,
        clientHeight: 720
      }
    },
    state,
    currentComponentGraphFocusNode: () => focusNode,
    signalLiveValueByName: () => null,
    isTraceEnabled: () => false
  });

  const result = service.renderComponentVisual({
    node: focusNode,
    model,
    rerender: () => {}
  });

  assert.equal(result.ok, true);
  assert.equal(renders > 0, true);
  assert.equal(canvas.width, 1280);
  assert.equal(canvas.height, 720);
  assert.equal(legendCanvas.width, 1280);
  assert.equal(legendCanvas.height, 720);
});
