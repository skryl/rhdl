import test from 'node:test';
import assert from 'node:assert/strict';
import { createExplorerModelRuntimeService } from '../../../../app/components/explorer/services/model_runtime_service.mjs';

test('explorer model runtime service manages selection and graph focus', () => {
  const rootNode = { id: 'root', path: 'top', rootId: 'root', children: ['child'], signals: [] };
  const childNode = { id: 'child', path: 'top.child', parentId: 'root', children: [], signals: [] };
  const state = {
    components: {
      model: {
        rootId: 'root',
        nodes: new Map([
          ['root', rootNode],
          ['child', childNode]
        ])
      },
      selectedNodeId: null,
      graphFocusId: null,
      graphShowChildren: false,
      graphLastTap: { nodeId: 'root', timeMs: 0 },
      graphHighlightedSignal: { signalName: 'x', liveName: null },
      graphLiveValues: new Map([['k', '1']]),
      sourceKey: '',
      parseError: ''
    }
  };

  const service = createExplorerModelRuntimeService({
    state,
    runtime: {},
    currentComponentSourceText: () => ''
  });

  service.ensureComponentSelection();
  service.ensureComponentGraphFocus();

  assert.equal(state.components.selectedNodeId, 'root');
  assert.equal(state.components.graphFocusId, 'root');
  assert.equal(state.components.graphShowChildren, true);

  const changed = service.setComponentGraphFocus('child', false);
  assert.equal(changed, true);
  assert.equal(state.components.selectedNodeId, 'child');
  assert.equal(state.components.graphFocusId, 'child');
  assert.equal(state.components.graphShowChildren, false);
  assert.equal(state.components.graphHighlightedSignal, null);
  assert.deepEqual(Array.from(state.components.graphLiveValues.entries()), []);
});

test('explorer model runtime service marks empty IR as not loaded', () => {
  const state = {
    components: {
      model: { rootId: 'root', nodes: new Map([['root', { id: 'root', children: [], signals: [] }]]) },
      selectedNodeId: 'root',
      graphFocusId: 'root',
      graphShowChildren: true,
      graphLastTap: null,
      graphHighlightedSignal: null,
      graphLiveValues: new Map(),
      sourceKey: 'old',
      parseError: ''
    }
  };

  const service = createExplorerModelRuntimeService({
    state,
    runtime: {},
    currentComponentSourceText: () => ''
  });

  service.refreshComponentExplorer();

  assert.equal(state.components.model, null);
  assert.equal(state.components.parseError, 'No IR loaded.');
  assert.equal(state.components.selectedNodeId, null);
  assert.equal(state.components.graphFocusId, null);
  assert.equal(state.components.graphShowChildren, false);
});

test('explorer model runtime service builds filtered tree rows', () => {
  const state = {
    components: {
      model: {
        rootId: 'root',
        nodes: new Map([
          ['root', { id: 'root', name: 'Top', kind: 'module', children: ['cpu'], signals: [] }],
          ['cpu', { id: 'cpu', name: 'CpuCore', kind: 'module', children: ['alu'], signals: [] }],
          ['alu', { id: 'alu', name: 'AluUnit', kind: 'module', children: [], signals: [] }]
        ])
      },
      selectedNodeId: 'cpu',
      graphFocusId: 'root',
      graphShowChildren: true,
      graphLastTap: null,
      graphHighlightedSignal: null,
      graphLiveValues: new Map(),
      sourceKey: 'k',
      parseError: ''
    }
  };

  const service = createExplorerModelRuntimeService({
    state,
    runtime: {},
    currentComponentSourceText: () => ''
  });

  const rows = service.buildComponentTreeRows('alu');
  assert.equal(rows.length, 3);
  assert.equal(rows[1].isActive, true);
  assert.equal(rows[2].name, 'AluUnit');
});
