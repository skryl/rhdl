import test from 'node:test';
import assert from 'node:assert/strict';

import { bindComponentBindings } from '../../../../app/components/explorer/bindings/bindings.mjs';

function makeTarget(extra = {}) {
  return Object.assign(new EventTarget(), extra);
}

test('bindComponentBindings handles component-select and teardown', () => {
  const calls = [];
  const dom = {
    componentTree: makeTarget(),
    componentGraphTopBtn: makeTarget(),
    componentGraphUpBtn: makeTarget(),
    irFileInput: makeTarget(),
    irJson: makeTarget({ value: '' })
  };

  const state = {
    components: {
      model: null,
      selectedNodeId: null
    }
  };

  const components = {
    renderTree: () => calls.push('renderTree'),
    setGraphFocus: () => calls.push('focus'),
    currentGraphFocusNode: () => null,
    renderViews: () => calls.push('renderViews'),
    clearSourceOverride: () => calls.push('clearOverride'),
    resetExplorerState: () => calls.push('resetExplorer'),
    isTabActive: () => false,
    refreshExplorer: () => calls.push('refreshExplorer')
  };

  const teardown = bindComponentBindings({
    dom,
    state,
    components,
    scheduleReduxUxSync: (reason) => calls.push(`sync:${reason}`),
    log: (msg) => calls.push(`log:${msg}`)
  });

  const event = new Event('component-select');
  event.detail = { nodeId: 'cpu.core' };
  dom.componentTree.dispatchEvent(event);

  assert.equal(state.components.selectedNodeId, 'cpu.core');
  assert.deepEqual(calls, ['renderTree', 'renderViews', 'sync:componentSelect']);

  teardown();
  const event2 = new Event('component-select');
  event2.detail = { nodeId: 'cpu.next' };
  dom.componentTree.dispatchEvent(event2);
  assert.equal(state.components.selectedNodeId, 'cpu.core');
});
