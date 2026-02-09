import test from 'node:test';
import assert from 'node:assert/strict';

import {
  summarizeExpr,
  componentSignalLookup,
  resolveNodeSignalRef,
  collectExprSignalNames
} from '../../../../app/components/explorer/lib/inspector_model.mjs';

test('explorer inspector model summarizeExpr handles core shapes', () => {
  assert.equal(summarizeExpr({ op: '+', left: { name: 'a' }, right: { value: 1, width: 8 } }), 'a + lit(1:8)');
  assert.equal(summarizeExpr({ selector: { name: 'sel' }, cases: [] }), 'mux(sel)');
  assert.equal(summarizeExpr(null), '-');
});

test('explorer inspector model resolveNodeSignalRef prefers lookup entries', () => {
  const signal = { name: 'clk', fullName: 'top.clk', liveName: 'top.clk', width: 1 };
  const ref = resolveNodeSignalRef({
    state: { components: {} },
    runtime: {},
    node: { path: 'top', pathTokens: ['top'] },
    lookup: new Map([['clk', signal]]),
    signalName: 'clk',
    width: 1
  });
  assert.deepEqual(ref, {
    name: 'clk',
    liveName: 'top.clk',
    width: 1,
    valueKey: 'top.clk'
  });
});

test('explorer inspector model collects unique expression signal names', () => {
  const names = collectExprSignalNames({
    left: { type: 'signal', name: 'a' },
    right: { type: 'signal', name: 'b' },
    nested: [{ type: 'signal', name: 'a' }]
  });
  assert.deepEqual(Array.from(names).sort(), ['a', 'b']);
});

test('explorer inspector model builds lookup across signal aliases', () => {
  const lookup = componentSignalLookup({
    signals: [{ name: 'clk', fullName: 'top.clk', liveName: 'top.clk' }]
  });
  assert.equal(lookup.has('clk'), true);
  assert.equal(lookup.has('top.clk'), true);
});
