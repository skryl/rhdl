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
