import test from 'node:test';
import assert from 'node:assert/strict';

import { LiveVcdParser } from '../../app/runtime/live_vcd_parser.mjs';

test('LiveVcdParser ingests wire declarations and scalar changes', () => {
  const parser = new LiveVcdParser(20);
  parser.ingest('$var wire 1 ! clk $end\n#0\n0!\n#5\n1!\n');

  assert.equal(parser.value('clk'), 1);
  assert.equal(parser.latestTime(), 5);
  assert.deepEqual(parser.series('clk'), [
    { t: 0, v: 0 },
    { t: 5, v: 1 }
  ]);
});

test('LiveVcdParser ingests vector changes and truncates old points', () => {
  const parser = new LiveVcdParser(2);
  parser.ingest('$var wire 8 " data $end\n#1\nb00000001 "\n#2\nb00000010 "\n#3\nb00000011 "\n');

  assert.equal(parser.value('data'), 3);
  assert.equal(parser.series('data').length, 2);
  assert.deepEqual(parser.series('data'), [
    { t: 2, v: 2 },
    { t: 3, v: 3 }
  ]);
});
