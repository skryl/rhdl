import test from 'node:test';
import assert from 'node:assert/strict';

import { currentIrSourceKey, parseIrMeta } from '../../app/lib/ir_meta_utils.mjs';

test('parseIrMeta collects signal widths and clock candidates', () => {
  const ir = {
    ports: [
      { name: 'clk', width: 1, direction: 'in' },
      { name: 'out_data', width: 8, direction: 'out' }
    ],
    nets: [{ name: 'u0__clk', width: 1 }],
    regs: [{ name: 'state', width: 3 }],
    processes: [{ clocked: true, clock: 'clk' }]
  };
  const meta = parseIrMeta(JSON.stringify(ir));

  assert.equal(meta.widths.get('clk'), 1);
  assert.equal(meta.widths.get('out_data'), 8);
  assert.equal(meta.signalInfo.get('state').kind, 'regs');
  assert.deepEqual(meta.clocks, ['clk']);
  assert.equal(meta.clockCandidates[0], 'clk');
});

test('currentIrSourceKey is stable for same text and changes with content', () => {
  const keyA1 = currentIrSourceKey('abc');
  const keyA2 = currentIrSourceKey('abc');
  const keyB = currentIrSourceKey('abd');

  assert.equal(keyA1, keyA2);
  assert.notEqual(keyA1, keyB);
  assert.equal(currentIrSourceKey(''), '');
});
