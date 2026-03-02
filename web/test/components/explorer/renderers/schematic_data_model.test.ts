import test from 'node:test';
import assert from 'node:assert/strict';
import { buildRenderList, applyLayoutPositions } from '../../../../app/components/explorer/renderers/schematic_data_model';

// --- fixtures ---

function minimalElements() {
  return [
    // symbol: focus component
    {
      data: {
        id: 'sym:cpu', label: 'CPU', nodeRole: 'symbol', symbolType: 'focus',
        componentId: 'cpu', path: 'top.cpu', direction: '',
        symbolWidth: 228, symbolHeight: 94
      },
      classes: 'schem-symbol schem-component schem-focus'
    },
    // symbol: child component
    {
      data: {
        id: 'sym:alu', label: 'ALU', nodeRole: 'symbol', symbolType: 'component',
        componentId: 'alu', path: 'top.cpu.alu', direction: '',
        symbolWidth: 178, symbolHeight: 72
      },
      classes: 'schem-symbol schem-component'
    },
    // pin on cpu
    {
      data: {
        id: 'pin:cpu:clk', label: 'clk', nodeRole: 'pin',
        symbolId: 'sym:cpu', side: 'left', order: 0, direction: 'in',
        signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk', width: 1
      },
      classes: 'schem-pin schem-pin-left'
    },
    // pin on cpu
    {
      data: {
        id: 'pin:cpu:data', label: 'data', nodeRole: 'pin',
        symbolId: 'sym:cpu', side: 'right', order: 0, direction: 'out',
        signalName: 'data', liveName: 'top__data', valueKey: 'top::data', width: 8
      },
      classes: 'schem-pin schem-pin-right schem-bus'
    },
    // pin on alu
    {
      data: {
        id: 'pin:alu:a', label: 'a', nodeRole: 'pin',
        symbolId: 'sym:alu', side: 'left', order: 0, direction: 'in',
        signalName: 'a', liveName: 'alu__a', valueKey: 'top.cpu::a', width: 8
      },
      classes: 'schem-pin schem-pin-left schem-bus'
    },
    // net
    {
      data: {
        id: 'net:cpu:clk', label: 'clk', nodeRole: 'net',
        signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk', width: 1, group: ''
      },
      classes: 'schem-net'
    },
    // wire: pin:cpu:clk -> net:cpu:clk
    {
      data: {
        id: 'wire:pin:cpu:clk:net:cpu:clk:from', source: 'pin:cpu:clk', target: 'net:cpu:clk',
        signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk',
        width: 1, direction: 'in', kind: 'port', segment: 'from', netId: 'net:cpu:clk'
      },
      classes: 'schem-wire schem-kind-port'
    },
    // wire: net:cpu:clk -> pin:alu:a
    {
      data: {
        id: 'wire:net:cpu:clk:pin:alu:a:to', source: 'net:cpu:clk', target: 'pin:alu:a',
        signalName: 'clk', liveName: 'top__clk', valueKey: 'top::clk',
        width: 1, direction: 'in', kind: 'port', segment: 'to', netId: 'net:cpu:clk'
      },
      classes: 'schem-wire schem-kind-port'
    }
  ];
}

// --- tests ---

test('buildRenderList returns correct structure from minimal elements', () => {
  const rl = buildRenderList(minimalElements());

  assert.ok(Array.isArray(rl.symbols), 'symbols is an array');
  assert.ok(Array.isArray(rl.pins), 'pins is an array');
  assert.ok(Array.isArray(rl.nets), 'nets is an array');
  assert.ok(Array.isArray(rl.wires), 'wires is an array');

  assert.equal(rl.symbols.length, 2, 'two symbols');
  assert.equal(rl.pins.length, 3, 'three pins');
  assert.equal(rl.nets.length, 1, 'one net');
  assert.equal(rl.wires.length, 2, 'two wires');
});

test('buildRenderList with empty input returns empty sub-arrays', () => {
  const rl = buildRenderList([]);
  assert.equal(rl.symbols.length, 0);
  assert.equal(rl.pins.length, 0);
  assert.equal(rl.nets.length, 0);
  assert.equal(rl.wires.length, 0);
});

test('buildRenderList with null/undefined input returns empty sub-arrays', () => {
  const rl1 = buildRenderList(null);
  assert.equal(rl1.symbols.length, 0);
  const rl2 = buildRenderList(undefined);
  assert.equal(rl2.symbols.length, 0);
});

test('buildRenderList derives symbol type from classes', () => {
  const rl = buildRenderList(minimalElements());
  const cpu = rl.symbols.find(s => s.id === 'sym:cpu')!;
  const alu = rl.symbols.find(s => s.id === 'sym:alu')!;

  assert.equal(cpu.type, 'focus', 'schem-focus -> type focus');
  assert.equal(alu.type, 'component', 'schem-component without schem-focus -> type component');
});

test('buildRenderList derives type for all class variants', () => {
  const elements = [
    { data: { id: 'a', nodeRole: 'symbol', symbolType: 'memory', symbolWidth: 124, symbolHeight: 56 }, classes: 'schem-symbol schem-memory' },
    { data: { id: 'b', nodeRole: 'symbol', symbolType: 'op', symbolWidth: 104, symbolHeight: 42 }, classes: 'schem-symbol schem-op' },
    { data: { id: 'c', nodeRole: 'symbol', symbolType: 'io', direction: 'in', symbolWidth: 34, symbolHeight: 16 }, classes: 'schem-symbol schem-io schem-io-in' }
  ];
  const rl = buildRenderList(elements);

  assert.equal(rl.symbols.find(s => s.id === 'a')!.type, 'memory');
  assert.equal(rl.symbols.find(s => s.id === 'b')!.type, 'op');
  assert.equal(rl.symbols.find(s => s.id === 'c')!.type, 'io');
});

test('buildRenderList symbols have expected fields', () => {
  const rl = buildRenderList(minimalElements());
  const cpu = rl.symbols.find(s => s.id === 'sym:cpu')!;

  assert.equal(cpu.label, 'CPU');
  assert.equal(cpu.componentId, 'cpu');
  assert.equal(cpu.path, 'top.cpu');
  assert.equal(cpu.width, 228);
  assert.equal(cpu.height, 94);
  assert.equal(typeof cpu.x, 'number');
  assert.equal(typeof cpu.y, 'number');
  assert.equal(cpu.classes, 'schem-symbol schem-component schem-focus');
});

test('buildRenderList pins have expected fields', () => {
  const rl = buildRenderList(minimalElements());
  const pin = rl.pins.find(p => p.id === 'pin:cpu:clk')!;

  assert.equal(pin.symbolId, 'sym:cpu');
  assert.equal(pin.side, 'left');
  assert.equal(pin.direction, 'in');
  assert.equal(pin.signalName, 'clk');
  assert.equal(pin.liveName, 'top__clk');
  assert.equal(pin.valueKey, 'top::clk');
  assert.equal(pin.signalWidth, 1);
  assert.equal(typeof pin.x, 'number');
  assert.equal(typeof pin.y, 'number');
});

test('buildRenderList pins detect bus from classes', () => {
  const rl = buildRenderList(minimalElements());
  const busPin = rl.pins.find(p => p.id === 'pin:cpu:data')!;
  const normalPin = rl.pins.find(p => p.id === 'pin:cpu:clk')!;

  assert.equal(busPin.bus, true);
  assert.equal(normalPin.bus, false);
});

test('buildRenderList nets have expected fields', () => {
  const rl = buildRenderList(minimalElements());
  const net = rl.nets[0];

  assert.equal(net.id, 'net:cpu:clk');
  assert.equal(net.label, 'clk');
  assert.equal(net.signalName, 'clk');
  assert.equal(net.liveName, 'top__clk');
  assert.equal(net.valueKey, 'top::clk');
  assert.equal(net.signalWidth, 1);
  assert.equal(net.bus, false);
  assert.equal(typeof net.x, 'number');
  assert.equal(typeof net.y, 'number');
});

test('buildRenderList nets detect bus from classes', () => {
  const elements = [
    {
      data: { id: 'net:bus', label: 'bus', nodeRole: 'net', signalName: 'bus', liveName: '', valueKey: 'k', width: 8 },
      classes: 'schem-net schem-bus'
    }
  ];
  const rl = buildRenderList(elements);
  assert.equal(rl.nets[0].bus, true);
});

test('buildRenderList wires have expected fields', () => {
  const rl = buildRenderList(minimalElements());
  const wire = rl.wires[0];

  assert.equal(wire.sourceId, 'pin:cpu:clk');
  assert.equal(wire.targetId, 'net:cpu:clk');
  assert.equal(wire.signalName, 'clk');
  assert.equal(wire.liveName, 'top__clk');
  assert.equal(wire.valueKey, 'top::clk');
  assert.equal(wire.signalWidth, 1);
  assert.equal(wire.direction, 'in');
  assert.equal(wire.kind, 'port');
});

test('buildRenderList wires detect bus from classes', () => {
  const elements = [
    { data: { id: 'p1', nodeRole: 'pin', symbolId: 's1', side: 'left', signalName: 'x', liveName: '', valueKey: 'k', width: 1 }, classes: 'schem-pin' },
    { data: { id: 'n1', nodeRole: 'net', signalName: 'x', liveName: '', valueKey: 'k', width: 8 }, classes: 'schem-net' },
    {
      data: { id: 'w1', source: 'p1', target: 'n1', signalName: 'x', liveName: '', valueKey: 'k', width: 8, direction: 'in', kind: 'port' },
      classes: 'schem-wire schem-bus'
    }
  ];
  const rl = buildRenderList(elements);
  assert.equal(rl.wires[0].bus, true);
});

test('buildRenderList wires detect bidir from classes', () => {
  const elements = [
    { data: { id: 'p1', nodeRole: 'pin', symbolId: 's1', side: 'left', signalName: 'x', liveName: '', valueKey: 'k', width: 1 }, classes: 'schem-pin' },
    { data: { id: 'n1', nodeRole: 'net', signalName: 'x', liveName: '', valueKey: 'k', width: 1 }, classes: 'schem-net' },
    {
      data: { id: 'w1', source: 'p1', target: 'n1', signalName: 'x', liveName: '', valueKey: 'k', width: 1, direction: 'inout', kind: 'port' },
      classes: 'schem-wire schem-bidir'
    }
  ];
  const rl = buildRenderList(elements);
  assert.equal(rl.wires[0].bidir, true);
});

test('buildRenderList default coordinates are zero', () => {
  const rl = buildRenderList(minimalElements());
  for (const sym of rl.symbols) {
    assert.equal(sym.x, 0);
    assert.equal(sym.y, 0);
  }
  for (const pin of rl.pins) {
    assert.equal(pin.x, 0);
    assert.equal(pin.y, 0);
  }
  for (const net of rl.nets) {
    assert.equal(net.x, 0);
    assert.equal(net.y, 0);
  }
});

test('buildRenderList creates byId index', () => {
  const rl = buildRenderList(minimalElements());
  assert.ok(rl.byId instanceof Map);
  assert.ok(rl.byId.has('sym:cpu'));
  assert.ok(rl.byId.has('pin:cpu:clk'));
  assert.ok(rl.byId.has('net:cpu:clk'));
  assert.strictEqual(rl.byId.get('sym:cpu'), rl.symbols.find(s => s.id === 'sym:cpu'));
});

// --- applyLayoutPositions tests ---

test('applyLayoutPositions updates symbol and net positions from ELK output', () => {
  const rl = buildRenderList(minimalElements());
  const elkOutput = {
    children: [
      { id: 'sym:cpu', x: 100, y: 200, width: 228, height: 94, ports: [] },
      { id: 'sym:alu', x: 400, y: 200, width: 178, height: 72, ports: [] },
      { id: 'net:cpu:clk', x: 300, y: 250, width: 52, height: 18 }
    ]
  };

  applyLayoutPositions(rl, elkOutput);

  const cpu = rl.symbols.find(s => s.id === 'sym:cpu')!;
  assert.equal(cpu.x, 100 + 228 * 0.5, 'symbol x = elkX + width/2');
  assert.equal(cpu.y, 200 + 94 * 0.5, 'symbol y = elkY + height/2');

  const net = rl.nets.find(n => n.id === 'net:cpu:clk')!;
  assert.equal(net.x, 300 + 52 * 0.5, 'net x = elkX + width/2');
  assert.equal(net.y, 250 + 18 * 0.5, 'net y = elkY + height/2');
});

test('applyLayoutPositions updates pin positions relative to parent symbol', () => {
  const rl = buildRenderList(minimalElements());
  const elkOutput = {
    children: [
      {
        id: 'sym:cpu', x: 100, y: 200, width: 228, height: 94,
        ports: [
          { id: 'pin:cpu:clk', x: 0, y: 20, width: 14, height: 10 },
          { id: 'pin:cpu:data', x: 214, y: 40, width: 14, height: 10 }
        ]
      },
      {
        id: 'sym:alu', x: 400, y: 200, width: 178, height: 72,
        ports: [
          { id: 'pin:alu:a', x: 0, y: 16, width: 14, height: 10 }
        ]
      },
      { id: 'net:cpu:clk', x: 300, y: 250, width: 52, height: 18 }
    ]
  };

  applyLayoutPositions(rl, elkOutput);

  const clkPin = rl.pins.find(p => p.id === 'pin:cpu:clk')!;
  assert.equal(clkPin.x, 100 + 0 + 14 * 0.5, 'pin x = parentElkX + portX + portWidth/2');
  assert.equal(clkPin.y, 200 + 20 + 10 * 0.5, 'pin y = parentElkY + portY + portHeight/2');

  const dataPin = rl.pins.find(p => p.id === 'pin:cpu:data')!;
  assert.equal(dataPin.x, 100 + 214 + 14 * 0.5);
  assert.equal(dataPin.y, 200 + 40 + 10 * 0.5);
});

test('applyLayoutPositions handles missing ELK entries gracefully', () => {
  const rl = buildRenderList(minimalElements());
  const elkOutput = {
    children: [
      { id: 'sym:cpu', x: 100, y: 200, width: 228, height: 94, ports: [] }
      // sym:alu and net:cpu:clk missing — should not throw
    ]
  };

  applyLayoutPositions(rl, elkOutput);

  const cpu = rl.symbols.find(s => s.id === 'sym:cpu')!;
  assert.equal(cpu.x, 100 + 228 * 0.5);

  const alu = rl.symbols.find(s => s.id === 'sym:alu')!;
  assert.equal(alu.x, 0, 'unmatched symbol stays at default');
  assert.equal(alu.y, 0);
});

test('applyLayoutPositions with null/undefined elkOutput does not throw', () => {
  const rl = buildRenderList(minimalElements());
  applyLayoutPositions(rl, null);
  applyLayoutPositions(rl, undefined);
  applyLayoutPositions(rl, {});
  applyLayoutPositions(rl, { children: null });
  // no assertion needed — just must not throw
});
