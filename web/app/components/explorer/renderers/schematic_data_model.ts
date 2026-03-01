// Renderer-agnostic data model.
// Converts schematic elements into a flat RenderList of typed primitives.

import {
  asRecord,
  type RenderList,
  type RenderNet,
  type RenderPin,
  type RenderSymbol,
  type RenderWire,
  type UnknownRecord
} from '../lib/types';

function deriveSymbolType(classes: unknown): string {
  const cls = String(classes || '');
  if (cls.includes('schem-focus')) return 'focus';
  if (cls.includes('schem-memory')) return 'memory';
  if (cls.includes('schem-op')) return 'op';
  if (cls.includes('schem-io')) return 'io';
  if (cls.includes('schem-component')) return 'component';
  return 'symbol';
}

function hasCls(classes: unknown, token: string): boolean {
  return String(classes || '').includes(token);
}

function readNumber(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function emptyRenderList(): RenderList {
  return {
    symbols: [],
    pins: [],
    nets: [],
    wires: [],
    byId: new Map<string, RenderSymbol | RenderPin | RenderNet | RenderWire>()
  };
}

function isRenderPin(value: unknown): value is RenderPin {
  const record = asRecord(value);
  return !!record && typeof record.symbolId === 'string';
}

export function buildRenderList(elements: unknown): RenderList {
  const renderList = emptyRenderList();
  if (!Array.isArray(elements)) {
    return renderList;
  }

  for (const el of elements) {
    const elementRecord = asRecord(el);
    const data = asRecord(elementRecord?.data);
    if (!elementRecord || !data) {
      continue;
    }

    const id = String(data.id || '').trim();
    if (!id) {
      continue;
    }

    const cls = String(elementRecord.classes || '');

    // Wire (edge) has source/target ids.
    const source = String(data.source || '').trim();
    const target = String(data.target || '').trim();
    if (source && target) {
      const wire: RenderWire = {
        id,
        sourceId: source,
        targetId: target,
        signalName: String(data.signalName || ''),
        liveName: String(data.liveName || ''),
        valueKey: String(data.valueKey || ''),
        signalWidth: readNumber(data.width, 1) || 1,
        direction: String(data.direction || ''),
        kind: String(data.kind || 'wire'),
        segment: String(data.segment || ''),
        netId: String(data.netId || ''),
        bus: hasCls(cls, 'schem-bus'),
        bidir: hasCls(cls, 'schem-bidir'),
        classes: cls,
        active: false,
        toggled: false,
        selected: false
      };
      renderList.wires.push(wire);
      renderList.byId.set(wire.id, wire);
      continue;
    }

    const role = String(data.nodeRole || '').trim();

    // Pin
    if (role === 'pin' || hasCls(cls, 'schem-pin')) {
      const pin: RenderPin = {
        id,
        label: String(data.label || ''),
        symbolId: String(data.symbolId || ''),
        side: String(data.side || 'left'),
        order: readNumber(data.order, 0),
        direction: String(data.direction || 'inout'),
        signalName: String(data.signalName || ''),
        liveName: String(data.liveName || ''),
        valueKey: String(data.valueKey || ''),
        signalWidth: readNumber(data.width, 1) || 1,
        bus: hasCls(cls, 'schem-bus'),
        classes: cls,
        x: 0,
        y: 0,
        width: 14,
        height: 10,
        active: false,
        toggled: false,
        selected: false
      };
      renderList.pins.push(pin);
      renderList.byId.set(pin.id, pin);
      continue;
    }

    // Net
    if (role === 'net' || hasCls(cls, 'schem-net')) {
      const net: RenderNet = {
        id,
        label: String(data.label || ''),
        signalName: String(data.signalName || ''),
        liveName: String(data.liveName || ''),
        valueKey: String(data.valueKey || ''),
        signalWidth: readNumber(data.width, 1) || 1,
        group: String(data.group || ''),
        bus: hasCls(cls, 'schem-bus'),
        classes: cls,
        x: 0,
        y: 0,
        width: 52,
        height: 18,
        active: false,
        toggled: false,
        selected: false
      };
      renderList.nets.push(net);
      renderList.byId.set(net.id, net);
      continue;
    }

    // Symbol (component/focus/io/memory/op)
    if (
      role === 'symbol'
      || role === 'component'
      || role === 'io'
      || role === 'memory'
      || role === 'op'
      || hasCls(cls, 'schem-symbol')
      || hasCls(cls, 'schem-component')
    ) {
      const sym: RenderSymbol = {
        id,
        label: String(data.label || ''),
        type: deriveSymbolType(cls),
        componentId: String(data.componentId || ''),
        path: String(data.path || ''),
        direction: String(data.direction || ''),
        classes: cls,
        x: 0,
        y: 0,
        width: readNumber(data.symbolWidth, 150),
        height: readNumber(data.symbolHeight, 64)
      };
      renderList.symbols.push(sym);
      renderList.byId.set(sym.id, sym);
    }
  }

  return renderList;
}

function mapElkChildren(elkOutput: UnknownRecord): Map<string, UnknownRecord> {
  const byId = new Map<string, UnknownRecord>();
  const children = Array.isArray(elkOutput.children) ? elkOutput.children : [];
  for (const child of children) {
    const childRecord = asRecord(child);
    if (!childRecord) {
      continue;
    }
    const id = String(childRecord.id || '').trim();
    if (!id) {
      continue;
    }
    byId.set(id, childRecord);
  }
  return byId;
}

export function applyLayoutPositions(renderList: RenderList, elkOutput: unknown): void {
  const elkRecord = asRecord(elkOutput);
  if (!elkRecord || !Array.isArray(elkRecord.children)) {
    return;
  }

  const childById = mapElkChildren(elkRecord);

  // Position symbols and attached pins.
  for (const sym of renderList.symbols) {
    const node = childById.get(sym.id);
    if (!node) {
      continue;
    }
    const w = readNumber(node.width, readNumber(sym.width, 150));
    const h = readNumber(node.height, readNumber(sym.height, 64));
    sym.x = readNumber(node.x, 0) + w * 0.5;
    sym.y = readNumber(node.y, 0) + h * 0.5;

    const ports = Array.isArray(node.ports) ? node.ports : [];
    for (const port of ports) {
      const portRecord = asRecord(port);
      if (!portRecord) {
        continue;
      }
      const pinCandidate = renderList.byId.get(String(portRecord.id || ''));
      if (!isRenderPin(pinCandidate)) {
        continue;
      }
      const pw = readNumber(portRecord.width, pinCandidate.width || 14);
      const ph = readNumber(portRecord.height, pinCandidate.height || 10);
      pinCandidate.x = readNumber(node.x, 0) + readNumber(portRecord.x, 0) + pw * 0.5;
      pinCandidate.y = readNumber(node.y, 0) + readNumber(portRecord.y, 0) + ph * 0.5;
    }
  }

  // Position nets.
  for (const net of renderList.nets) {
    const node = childById.get(net.id);
    if (!node) {
      continue;
    }
    const w = readNumber(node.width, net.width || 52);
    const h = readNumber(node.height, net.height || 18);
    net.x = readNumber(node.x, 0) + w * 0.5;
    net.y = readNumber(node.y, 0) + h * 0.5;
  }
}
