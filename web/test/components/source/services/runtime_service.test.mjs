import test from 'node:test';
import assert from 'node:assert/strict';
import { createSourceRuntimeService } from '../../../../app/components/source/services/runtime_service.mjs';

test('source runtime service manages source and schematic bundles', () => {
  const state = {
    components: {
      sourceBundle: null,
      sourceBundleByClass: new Map(),
      sourceBundleByModule: new Map(),
      schematicBundle: null,
      schematicBundleByPath: new Map(),
      overrideSource: '',
      overrideMeta: null
    }
  };
  const service = createSourceRuntimeService({
    dom: {},
    state,
    currentRunnerPreset: () => ({ id: 'generic', usesManualIr: true }),
    normalizeComponentSourceBundle: (bundle) => bundle,
    normalizeComponentSchematicBundle: (bundle) => bundle,
    destroyComponentGraph: () => {}
  });

  service.setComponentSourceBundle({
    byClass: new Map([['A', {}]]),
    byModule: new Map([['top', {}]])
  });
  service.setComponentSchematicBundle({
    byPath: new Map([['top.cpu', {}]])
  });
  assert.equal(state.components.sourceBundleByClass.size, 1);
  assert.equal(state.components.sourceBundleByModule.size, 1);
  assert.equal(state.components.schematicBundleByPath.size, 1);

  service.clearComponentSourceBundle();
  service.clearComponentSchematicBundle();
  assert.equal(state.components.sourceBundleByClass.size, 0);
  assert.equal(state.components.schematicBundleByPath.size, 0);
});

test('source runtime service resets explorer and updates source visibility', () => {
  const dom = {
    irJson: { value: '{"ir":1}' },
    irSourceSection: { hidden: false },
    componentTree: {
      setFilterCalls: [],
      setFilter(value, emit) {
        this.setFilterCalls.push([value, emit]);
      }
    }
  };
  const state = {
    components: {
      model: { rootId: 'top' },
      selectedNodeId: 'node_1',
      parseError: 'x',
      sourceKey: 'k',
      graphFocusId: 'node_1',
      graphShowChildren: true,
      graphLastTap: { nodeId: 'node_1', timeMs: 1 },
      graphHighlightedSignal: { signalName: 'x' },
      graphLiveValues: new Map([['k', '1']]),
      graphLayoutEngine: 'elk',
      sourceBundle: { byClass: new Map(), byModule: new Map() },
      sourceBundleByClass: new Map([['X', {}]]),
      sourceBundleByModule: new Map([['Y', {}]]),
      schematicBundle: { byPath: new Map() },
      schematicBundleByPath: new Map([['Z', {}]]),
      overrideSource: '',
      overrideMeta: null
    }
  };
  let destroyCalls = 0;
  const service = createSourceRuntimeService({
    dom,
    state,
    currentRunnerPreset: () => ({ id: 'apple2', usesManualIr: false }),
    normalizeComponentSourceBundle: () => null,
    normalizeComponentSchematicBundle: () => null,
    destroyComponentGraph: () => {
      destroyCalls += 1;
    }
  });

  service.setComponentSourceOverride('hello', { x: 1 });
  assert.equal(service.currentComponentSourceText(), 'hello');
  service.clearComponentSourceOverride();
  assert.equal(service.currentComponentSourceText(), '{"ir":1}');

  service.updateIrSourceVisibility();
  assert.equal(dom.irSourceSection.hidden, true);

  service.resetComponentExplorerState();
  assert.equal(state.components.model, null);
  assert.equal(state.components.selectedNodeId, null);
  assert.equal(state.components.graphLayoutEngine, 'none');
  assert.equal(state.components.sourceBundleByClass.size, 0);
  assert.equal(state.components.schematicBundleByPath.size, 0);
  assert.equal(destroyCalls, 1);
  assert.deepEqual(dom.componentTree.setFilterCalls, [['', false]]);
});
