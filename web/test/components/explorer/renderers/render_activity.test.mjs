import test from 'node:test';
import assert from 'node:assert/strict';
import { updateRenderActivity } from '../../../../app/components/explorer/renderers/render_activity.mjs';

function makeRenderList() {
  const net1 = { id: 'n1', signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk', active: false, toggled: false, selected: false };
  const net2 = { id: 'n2', signalName: 'data', liveName: 'top__data', valueKey: 'top::data', active: false, toggled: false, selected: false };
  const pin1 = { id: 'p1', signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk', active: false, toggled: false, selected: false };
  const wire1 = { id: 'w1', signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk', active: false, toggled: false, selected: false };
  return {
    symbols: [],
    pins: [pin1],
    nets: [net1, net2],
    wires: [wire1],
    byId: new Map([['n1', net1], ['n2', net2], ['p1', pin1], ['w1', wire1]])
  };
}

const toBigInt = (v) => {
  if (v == null) return 0n;
  try { return BigInt(v); } catch { return 0n; }
};

test('updateRenderActivity sets active when value is non-zero', () => {
  const rl = makeRenderList();
  const prev = new Map();
  const values = { 'top__clk': 1n, 'top__data': 0n };

  updateRenderActivity({
    renderList: rl,
    signalLiveValueByName: (name) => values[name] ?? null,
    toBigInt,
    highlightedSignal: null,
    previousValues: prev
  });

  assert.equal(rl.nets.find(n => n.id === 'n1').active, true, 'clk=1 -> active');
  assert.equal(rl.nets.find(n => n.id === 'n2').active, false, 'data=0 -> not active');
  assert.equal(rl.pins.find(p => p.id === 'p1').active, true, 'pin for clk -> active');
});

test('updateRenderActivity sets toggled when value changes', () => {
  const rl = makeRenderList();
  const prev = new Map([['top::clk', '0'], ['top::data', '5']]);
  const values = { 'top__clk': 1n, 'top__data': 5n };

  updateRenderActivity({
    renderList: rl,
    signalLiveValueByName: (name) => values[name] ?? null,
    toBigInt,
    highlightedSignal: null,
    previousValues: prev
  });

  assert.equal(rl.nets.find(n => n.id === 'n1').toggled, true, 'clk changed 0->1 -> toggled');
  assert.equal(rl.nets.find(n => n.id === 'n2').toggled, false, 'data unchanged -> not toggled');
});

test('updateRenderActivity sets selected when signal matches highlight', () => {
  const rl = makeRenderList();
  const prev = new Map();
  const values = { 'top__clk': 1n, 'top__data': 0n };

  updateRenderActivity({
    renderList: rl,
    signalLiveValueByName: (name) => values[name] ?? null,
    toBigInt,
    highlightedSignal: { signalName: null, liveName: 'top__clk' },
    previousValues: prev
  });

  assert.equal(rl.nets.find(n => n.id === 'n1').selected, true, 'clk matches highlight');
  assert.equal(rl.nets.find(n => n.id === 'n2').selected, false, 'data does not match');
});

test('updateRenderActivity selected matches by signalName', () => {
  const rl = makeRenderList();
  const prev = new Map();

  updateRenderActivity({
    renderList: rl,
    signalLiveValueByName: () => null,
    toBigInt,
    highlightedSignal: { signalName: 'data', liveName: null },
    previousValues: prev
  });

  assert.equal(rl.nets.find(n => n.id === 'n2').selected, true);
  assert.equal(rl.nets.find(n => n.id === 'n1').selected, false);
});

test('updateRenderActivity propagates state to wires via valueKey', () => {
  const rl = makeRenderList();
  const prev = new Map([['top::clk', '0']]);
  const values = { 'top__clk': 1n };

  updateRenderActivity({
    renderList: rl,
    signalLiveValueByName: (name) => values[name] ?? null,
    toBigInt,
    highlightedSignal: { signalName: null, liveName: 'top__clk' },
    previousValues: prev
  });

  const wire = rl.wires.find(w => w.id === 'w1');
  assert.equal(wire.active, true);
  assert.equal(wire.toggled, true);
  assert.equal(wire.selected, true);
});

test('updateRenderActivity returns nextValues map', () => {
  const rl = makeRenderList();
  const prev = new Map();
  const values = { 'top__clk': 42n, 'top__data': 0n };

  const next = updateRenderActivity({
    renderList: rl,
    signalLiveValueByName: (name) => values[name] ?? null,
    toBigInt,
    highlightedSignal: null,
    previousValues: prev
  });

  assert.ok(next instanceof Map);
  assert.equal(next.get('top::clk'), '42');
  assert.equal(next.get('top::data'), '0');
});
