import test from 'node:test';
import assert from 'node:assert/strict';
import { buildSpatialIndex } from '../../../../app/components/explorer/renderers/spatial_index.mjs';

function makeRenderList() {
  const sym1 = { id: 's1', type: 'component', x: 100, y: 100, width: 178, height: 72, componentId: 'cpu' };
  const sym2 = { id: 's2', type: 'component', x: 400, y: 100, width: 178, height: 72, componentId: 'alu' };
  const sym3 = { id: 's3', type: 'focus', x: 250, y: 300, width: 228, height: 94, componentId: 'top' };
  const pin1 = { id: 'p1', x: 100, y: 80, width: 14, height: 10, symbolId: 's1', signalName: 'clk', liveName: 'clk' };
  const net1 = { id: 'n1', x: 250, y: 100, width: 52, height: 18, signalName: 'bus', liveName: 'bus' };
  return {
    symbols: [sym1, sym2, sym3],
    pins: [pin1],
    nets: [net1],
    wires: [],
    byId: new Map([['s1', sym1], ['s2', sym2], ['s3', sym3], ['p1', pin1], ['n1', net1]])
  };
}

test('buildSpatialIndex returns object with queryPoint', () => {
  const index = buildSpatialIndex(makeRenderList());
  assert.equal(typeof index.queryPoint, 'function');
});

test('queryPoint inside symbol s2 returns s2', () => {
  const index = buildSpatialIndex(makeRenderList());
  const hit = index.queryPoint(400, 100);
  assert.ok(hit, 'should find a hit');
  assert.equal(hit.id, 's2');
});

test('queryPoint outside all elements returns null', () => {
  const index = buildSpatialIndex(makeRenderList());
  const hit = index.queryPoint(9999, 9999);
  assert.equal(hit, null);
});

test('queryPoint where pin overlaps symbol returns pin (higher priority)', () => {
  const index = buildSpatialIndex(makeRenderList());
  // pin p1 is at (100, 80) with 14x10 — its bbox covers (93, 75) to (107, 85)
  // symbol s1 is at (100, 100) with 178x72 — its bbox covers (11, 64) to (189, 136)
  // point (100, 80) is inside both
  const hit = index.queryPoint(100, 80);
  assert.ok(hit, 'should find a hit');
  assert.equal(hit.id, 'p1', 'pin should take priority over symbol');
});

test('queryPoint where net is present returns net (higher priority than symbol)', () => {
  const index = buildSpatialIndex(makeRenderList());
  // net n1 at (250, 100) with 52x18 — bbox (224, 91) to (276, 109)
  // symbol s3 at (250, 300) — not overlapping
  const hit = index.queryPoint(250, 100);
  assert.ok(hit);
  assert.equal(hit.id, 'n1');
});

test('queryPoint with empty renderList returns null', () => {
  const index = buildSpatialIndex({ symbols: [], pins: [], nets: [], wires: [], byId: new Map() });
  assert.equal(index.queryPoint(0, 0), null);
});

test('returned hit has element reference', () => {
  const rl = makeRenderList();
  const index = buildSpatialIndex(rl);
  const hit = index.queryPoint(400, 100);
  assert.strictEqual(hit, rl.byId.get('s2'));
});
