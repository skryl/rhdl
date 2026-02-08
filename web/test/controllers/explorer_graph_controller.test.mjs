import test from 'node:test';
import assert from 'node:assert/strict';
import { createExplorerGraphController } from '../../app/controllers/explorer_graph_controller.mjs';

function createNoopGraphController(overrides = {}) {
  return createExplorerGraphController({
    dom: {},
    state: {
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
        graphLiveValues: new Map(),
        graphHighlightedSignal: null,
        graphShowChildren: true,
        model: null,
        sourceKey: ''
      }
    },
    runtime: {},
    currentComponentGraphFocusNode: () => null,
    currentSelectedComponentNode: () => null,
    renderComponentTree: () => {},
    renderComponentViews: () => {},
    signalLiveValueByName: () => null,
    componentSignalLookup: () => new Map(),
    resolveNodeSignalRef: () => null,
    collectExprSignalNames: () => new Set(),
    findComponentSchematicEntry: () => null,
    summarizeExpr: () => '-',
    renderComponentLiveSignals: () => {},
    renderComponentConnections: () => {},
    ...overrides
  });
}

test('explorer graph controller resets graph runtime state on destroy', () => {
  const state = {
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
      graphLiveValues: new Map(),
      graphHighlightedSignal: null,
      graphShowChildren: true,
      model: null,
      sourceKey: ''
    }
  };

  const controller = createNoopGraphController({ state });
  const graphRef = state.components.graph;

  controller.destroyComponentGraph();

  assert.equal(graphRef.destroyed, true);
  assert.equal(state.components.graph, null);
  assert.equal(state.components.graphKey, '');
  assert.equal(state.components.graphSelectedId, null);
  assert.equal(state.components.graphLastTap, null);
  assert.equal(state.components.graphLayoutEngine, 'none');
  assert.equal(state.components.graphElkAvailable, false);
});

test('explorer graph controller validates required callbacks', () => {
  assert.throws(
    () => createNoopGraphController({ renderComponentTree: null }),
    /requires function: renderComponentTree/
  );
});
