// Renderer-agnostic data model.
// Converts schematic elements into a flat RenderList of typed primitives.

const SYMBOL_TYPES = ['focus', 'memory', 'op', 'io', 'component'];

function deriveSymbolType(classes: any) {
  const cls = String(classes || '');
  if (cls.includes('schem-focus')) return 'focus';
  if (cls.includes('schem-memory')) return 'memory';
  if (cls.includes('schem-op')) return 'op';
  if (cls.includes('schem-io')) return 'io';
  if (cls.includes('schem-component')) return 'component';
  return 'symbol';
}

function hasCls(classes: any, token: any) {
  return String(classes || '').includes(token);
}

export function buildRenderList(elements: any) {
  const symbols: any[] = [];
  const pins: any[] = [];
  const nets: any[] = [];
  const wires: any[] = [];
  const byId = new Map();

  if (!Array.isArray(elements)) {
    return { symbols, pins, nets, wires, byId };
  }

  for (const el of elements) {
    if (!el || !el.data) continue;
    const d = el.data;
    const cls = String(el.classes || '');

    // wire (edge) — has source/target
    if (d.source && d.target) {
      const wire = {
        id: d.id,
        sourceId: d.source,
        targetId: d.target,
        signalName: d.signalName || '',
        liveName: d.liveName || '',
        valueKey: d.valueKey || '',
        signalWidth: Number(d.width) || 1,
        direction: d.direction || '',
        kind: d.kind || 'wire',
        segment: d.segment || '',
        netId: d.netId || '',
        bus: hasCls(cls, 'schem-bus'),
        bidir: hasCls(cls, 'schem-bidir'),
        classes: cls,
        // live state (mutated by render_activity)
        active: false,
        toggled: false,
        selected: false
      };
      wires.push(wire);
      byId.set(wire.id, wire);
      continue;
    }

    const role = String(d.nodeRole || '');

    // pin
    if (role === 'pin' || hasCls(cls, 'schem-pin')) {
      const pin = {
        id: d.id,
        label: d.label || '',
        symbolId: d.symbolId || '',
        side: d.side || 'left',
        order: Number(d.order) || 0,
        direction: d.direction || 'inout',
        signalName: d.signalName || '',
        liveName: d.liveName || '',
        valueKey: d.valueKey || '',
        signalWidth: Number(d.width) || 1,
        bus: hasCls(cls, 'schem-bus'),
        classes: cls,
        x: 0,
        y: 0,
        width: 14,
        height: 10,
        // live state
        active: false,
        toggled: false,
        selected: false
      };
      pins.push(pin);
      byId.set(pin.id, pin);
      continue;
    }

    // net
    if (role === 'net' || hasCls(cls, 'schem-net')) {
      const net = {
        id: d.id,
        label: d.label || '',
        signalName: d.signalName || '',
        liveName: d.liveName || '',
        valueKey: d.valueKey || '',
        signalWidth: Number(d.width) || 1,
        group: d.group || '',
        bus: hasCls(cls, 'schem-bus'),
        classes: cls,
        x: 0,
        y: 0,
        width: 52,
        height: 18,
        // live state
        active: false,
        toggled: false,
        selected: false
      };
      nets.push(net);
      byId.set(net.id, net);
      continue;
    }

    // symbol (component, focus, io, memory, op)
    if (role === 'symbol' || role === 'component' || role === 'io' || role === 'memory' || role === 'op' ||
        hasCls(cls, 'schem-symbol') || hasCls(cls, 'schem-component')) {
      const sym = {
        id: d.id,
        label: d.label || '',
        type: deriveSymbolType(cls),
        componentId: d.componentId || '',
        path: d.path || '',
        direction: d.direction || '',
        classes: cls,
        x: 0,
        y: 0,
        width: Number(d.symbolWidth) || 150,
        height: Number(d.symbolHeight) || 64
      };
      symbols.push(sym);
      byId.set(sym.id, sym);
      continue;
    }
  }

  return { symbols, pins, nets, wires, byId };
}

export function applyLayoutPositions(renderList: any, elkOutput: any) {
  if (!renderList || !elkOutput || !Array.isArray(elkOutput.children)) {
    return;
  }

  const childById = new Map();
  for (const child of elkOutput.children) {
    childById.set(String(child.id || ''), child);
  }

  // position symbols and their pins
  for (const sym of renderList.symbols) {
    const node = childById.get(sym.id);
    if (!node) continue;
    const w = Number(node.width) || sym.width;
    const h = Number(node.height) || sym.height;
    sym.x = (Number(node.x) || 0) + w * 0.5;
    sym.y = (Number(node.y) || 0) + h * 0.5;

    // position pins belonging to this symbol
    const ports = Array.isArray(node.ports) ? node.ports : [];
    for (const port of ports) {
      const pin = renderList.byId.get(String(port.id || ''));
      if (!pin) continue;
      const pw = Number(port.width) || pin.width || 14;
      const ph = Number(port.height) || pin.height || 10;
      pin.x = (Number(node.x) || 0) + (Number(port.x) || 0) + pw * 0.5;
      pin.y = (Number(node.y) || 0) + (Number(port.y) || 0) + ph * 0.5;
    }
  }

  // position nets
  for (const net of renderList.nets) {
    const node = childById.get(net.id);
    if (!node) continue;
    const w = Number(node.width) || net.width || 52;
    const h = Number(node.height) || net.height || 18;
    net.x = (Number(node.x) || 0) + w * 0.5;
    net.y = (Number(node.y) || 0) + h * 0.5;
  }
}
