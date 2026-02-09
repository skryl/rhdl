import test from 'node:test';
import assert from 'node:assert/strict';
import { createExplorerInspectorController } from '../../../../app/components/explorer/controllers/inspector_controller.mjs';

function createNoopRenderers() {
  const noop = () => {};
  return {
    renderComponentInspectorView: noop,
    renderComponentLiveSignalsView: noop,
    renderComponentConnectionsView: noop,
    clearComponentConnectionsView: noop
  };
}

test('explorer inspector summarizeExpr formats representative expressions', () => {
  const controller = createExplorerInspectorController({
    dom: {},
    state: { components: {} },
    runtime: {},
    ...createNoopRenderers()
  });

  assert.equal(controller.summarizeExpr({ op: '+', left: { name: 'a' }, right: { value: 1, width: 8 } }), 'a + lit(1:8)');
  assert.equal(controller.summarizeExpr({ selector: { name: 'sel' }, cases: [] }), 'mux(sel)');
  assert.equal(controller.summarizeExpr(null), '-');
});

test('explorer inspector resolveNodeSignalRef resolves live names from lookup', () => {
  const signal = { name: 'clk', fullName: 'top.clk', liveName: 'top.clk', width: 1 };
  const controller = createExplorerInspectorController({
    dom: {},
    state: { components: {} },
    runtime: {},
    ...createNoopRenderers()
  });

  const ref = controller.resolveNodeSignalRef(
    { path: 'top', pathTokens: ['top'] },
    new Map([
      ['clk', signal]
    ]),
    'clk',
    1
  );

  assert.deepEqual(ref, {
    name: 'clk',
    liveName: 'top.clk',
    width: 1,
    valueKey: 'top.clk'
  });
});
