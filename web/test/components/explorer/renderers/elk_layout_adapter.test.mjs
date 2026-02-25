import test from 'node:test';
import assert from 'node:assert/strict';
import { buildElkGraph, applyElkResult, elkPortLayoutOptions, toElkPortSide } from '../../../../app/components/explorer/renderers/elk_layout_adapter.mjs';

function makeRenderList() {
  return {
    symbols: [
      { id: 'sym:cpu', type: 'focus', x: 0, y: 0, width: 228, height: 94 },
      { id: 'sym:alu', type: 'component', x: 0, y: 0, width: 178, height: 72 }
    ],
    pins: [
      { id: 'pin:cpu:clk', symbolId: 'sym:cpu', side: 'left', order: 0, width: 14, height: 10, x: 0, y: 0 },
      { id: 'pin:cpu:data', symbolId: 'sym:cpu', side: 'right', order: 0, width: 14, height: 10, x: 0, y: 0 },
      { id: 'pin:alu:a', symbolId: 'sym:alu', side: 'left', order: 0, width: 14, height: 10, x: 0, y: 0 }
    ],
    nets: [
      { id: 'net:clk', x: 0, y: 0, width: 52, height: 18 }
    ],
    wires: [
      { id: 'w1', sourceId: 'pin:cpu:clk', targetId: 'net:clk' },
      { id: 'w2', sourceId: 'net:clk', targetId: 'pin:alu:a' }
    ],
    byId: new Map()
  };
}

test('elkPortLayoutOptions returns expected algorithm and direction', () => {
  const opts = elkPortLayoutOptions();
  assert.equal(opts.algorithm, 'layered');
  assert.equal(opts['elk.direction'], 'RIGHT');
  assert.equal(opts['elk.edgeRouting'], 'ORTHOGONAL');
});

test('toElkPortSide maps sides correctly', () => {
  assert.equal(toElkPortSide('left'), 'WEST');
  assert.equal(toElkPortSide('right'), 'EAST');
  assert.equal(toElkPortSide('top'), 'NORTH');
  assert.equal(toElkPortSide('bottom'), 'SOUTH');
  assert.equal(toElkPortSide('unknown'), 'WEST');
  assert.equal(toElkPortSide(''), 'WEST');
});

test('buildElkGraph creates children for symbols and nets', () => {
  const rl = makeRenderList();
  const graph = buildElkGraph(rl);

  assert.equal(graph.id, 'root');
  assert.ok(Array.isArray(graph.children));
  // 2 symbols + 1 net = 3 children
  assert.equal(graph.children.length, 3);

  const cpuChild = graph.children.find(c => c.id === 'sym:cpu');
  assert.ok(cpuChild);
  assert.equal(cpuChild.width, 228);
  assert.equal(cpuChild.height, 94);
});

test('buildElkGraph includes ports on symbol children', () => {
  const rl = makeRenderList();
  const graph = buildElkGraph(rl);

  const cpuChild = graph.children.find(c => c.id === 'sym:cpu');
  assert.ok(Array.isArray(cpuChild.ports));
  assert.equal(cpuChild.ports.length, 2); // clk + data

  const clkPort = cpuChild.ports.find(p => p.id === 'pin:cpu:clk');
  assert.ok(clkPort);
  assert.equal(clkPort.layoutOptions['elk.port.side'], 'WEST');
});

test('buildElkGraph includes edges for wires', () => {
  const rl = makeRenderList();
  const graph = buildElkGraph(rl);

  assert.ok(Array.isArray(graph.edges));
  assert.equal(graph.edges.length, 2);
  assert.deepEqual(graph.edges[0].sources, ['pin:cpu:clk']);
  assert.deepEqual(graph.edges[0].targets, ['net:clk']);
});

test('buildElkGraph includes layout options', () => {
  const rl = makeRenderList();
  const graph = buildElkGraph(rl);

  assert.equal(graph.layoutOptions.algorithm, 'layered');
  assert.equal(graph.layoutOptions['elk.direction'], 'RIGHT');
});

test('applyElkResult positions symbols, pins, and nets', () => {
  const rl = makeRenderList();
  // populate byId
  for (const s of rl.symbols) rl.byId.set(s.id, s);
  for (const p of rl.pins) rl.byId.set(p.id, p);
  for (const n of rl.nets) rl.byId.set(n.id, n);

  const elkResult = {
    children: [
      {
        id: 'sym:cpu', x: 100, y: 50, width: 228, height: 94,
        ports: [
          { id: 'pin:cpu:clk', x: 0, y: 20, width: 14, height: 10 },
          { id: 'pin:cpu:data', x: 214, y: 40, width: 14, height: 10 }
        ]
      },
      {
        id: 'sym:alu', x: 400, y: 50, width: 178, height: 72,
        ports: [
          { id: 'pin:alu:a', x: 0, y: 16, width: 14, height: 10 }
        ]
      },
      { id: 'net:clk', x: 300, y: 80, width: 52, height: 18 }
    ]
  };

  applyElkResult(rl, elkResult);

  const cpu = rl.symbols.find(s => s.id === 'sym:cpu');
  assert.equal(cpu.x, 100 + 228 * 0.5);
  assert.equal(cpu.y, 50 + 94 * 0.5);

  const clkPin = rl.pins.find(p => p.id === 'pin:cpu:clk');
  assert.equal(clkPin.x, 100 + 0 + 14 * 0.5);
  assert.equal(clkPin.y, 50 + 20 + 10 * 0.5);

  const net = rl.nets.find(n => n.id === 'net:clk');
  assert.equal(net.x, 300 + 52 * 0.5);
  assert.equal(net.y, 80 + 18 * 0.5);
});

test('applyElkResult handles null gracefully', () => {
  const rl = makeRenderList();
  applyElkResult(rl, null);
  applyElkResult(rl, {});
  applyElkResult(rl, { children: null });
  // should not throw
});
