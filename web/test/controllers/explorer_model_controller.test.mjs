import test from 'node:test';
import assert from 'node:assert/strict';
import { createExplorerModelController } from '../../app/controllers/explorer_model_controller.mjs';

test('explorer model controller manages selection and graph focus', () => {
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

  const controller = createExplorerModelController({
    dom: {},
    state,
    runtime: {},
    currentComponentSourceText: () => '',
    renderComponentTreeRows: () => {}
  });

  controller.ensureComponentSelection();
  controller.ensureComponentGraphFocus();

  assert.equal(state.components.selectedNodeId, 'root');
  assert.equal(state.components.graphFocusId, 'root');
  assert.equal(state.components.graphShowChildren, true);

  const changed = controller.setComponentGraphFocus('child', false);
  assert.equal(changed, true);
  assert.equal(state.components.selectedNodeId, 'child');
  assert.equal(state.components.graphFocusId, 'child');
  assert.equal(state.components.graphShowChildren, false);
  assert.equal(state.components.graphHighlightedSignal, null);
  assert.deepEqual(Array.from(state.components.graphLiveValues.entries()), []);
});

test('explorer model controller marks empty IR as not loaded', () => {
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

  const controller = createExplorerModelController({
    dom: {},
    state,
    runtime: {},
    currentComponentSourceText: () => '',
    renderComponentTreeRows: () => {}
  });

  controller.refreshComponentExplorer();

  assert.equal(state.components.model, null);
  assert.equal(state.components.parseError, 'No IR loaded.');
  assert.equal(state.components.selectedNodeId, null);
  assert.equal(state.components.graphFocusId, null);
  assert.equal(state.components.graphShowChildren, false);
});
