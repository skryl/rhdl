// ELK layout adapter for the RenderList.
// Builds an ELK graph from the RenderList, runs layout, and applies positions back.

import {
  asRecord,
  type RenderList,
  type RenderPin,
  type RenderWire,
  type UnknownRecord
} from '../lib/types';

interface ElkPort {
  id: string;
  width: number;
  height: number;
  x?: number;
  y?: number;
  layoutOptions?: Record<string, string>;
}

interface ElkNode {
  id: string;
  width?: number;
  height?: number;
  x?: number;
  y?: number;
  ports?: ElkPort[];
}

interface ElkSectionPoint {
  x: number;
  y: number;
}

interface ElkSection {
  startPoint?: ElkSectionPoint;
  bendPoints?: ElkSectionPoint[];
  endPoint?: ElkSectionPoint;
}

interface ElkEdge {
  id: string;
  sources?: string[];
  targets?: string[];
  sections?: ElkSection[];
}

interface ElkGraph {
  id: string;
  children: ElkNode[];
  edges: ElkEdge[];
  layoutOptions: ReturnType<typeof elkPortLayoutOptions>;
}

interface ElkResult {
  children?: ElkNode[];
  edges?: ElkEdge[];
}

type ElkCtor = new () => {
  layout: (graph: ElkGraph) => Promise<ElkResult>;
};

export function elkPortLayoutOptions() {
  return {
    algorithm: 'layered',
    'elk.direction': 'RIGHT',
    'elk.edgeRouting': 'ORTHOGONAL',
    'elk.layered.crossingMinimization.strategy': 'LAYER_SWEEP',
    'elk.layered.nodePlacement.strategy': 'NETWORK_SIMPLEX',
    'elk.layered.nodePlacement.favorStraightEdges': true,
    'elk.layered.considerModelOrder.strategy': 'NODES_AND_EDGES',
    'elk.layered.spacing.nodeNodeBetweenLayers': 170,
    'elk.spacing.nodeNode': 96,
    'elk.spacing.edgeNode': 64,
    'elk.spacing.edgeEdge': 30,
    'elk.padding': '[left=90,top=60,right=90,bottom=60]',
    'elk.separateConnectedComponents': true
  };
}

export function toElkPortSide(side: unknown): 'WEST' | 'EAST' | 'NORTH' | 'SOUTH' {
  const raw = String(side || '').toLowerCase();
  if (raw === 'left') return 'WEST';
  if (raw === 'right') return 'EAST';
  if (raw === 'top') return 'NORTH';
  if (raw === 'bottom') return 'SOUTH';
  return 'WEST';
}

export function buildElkGraph(renderList: RenderList): ElkGraph {
  const children: ElkNode[] = [];

  const pinsBySymbol = new Map<string, RenderPin[]>();
  for (const pin of renderList.pins) {
    const sid = pin.symbolId;
    if (!sid) {
      continue;
    }
    const list = pinsBySymbol.get(sid) || [];
    list.push(pin);
    pinsBySymbol.set(sid, list);
  }

  for (const sym of renderList.symbols) {
    const ports: ElkPort[] = (pinsBySymbol.get(sym.id) || []).map((pin) => ({
      id: pin.id,
      width: Math.max(8, pin.width || 12),
      height: Math.max(6, pin.height || 8),
      layoutOptions: {
        'elk.port.side': toElkPortSide(pin.side),
        'elk.port.index': String(Number(pin.order) || 0)
      }
    }));

    children.push({
      id: sym.id,
      width: Math.max(92, sym.width || 150),
      height: Math.max(36, sym.height || 64),
      ports,
      layoutOptions: {
        'elk.portConstraints': 'FIXED_SIDE'
      }
    } as ElkNode & UnknownRecord);
  }

  for (const net of renderList.nets) {
    children.push({
      id: net.id,
      width: Math.max(26, net.width || 52),
      height: Math.max(12, net.height || 18)
    });
  }

  const edges: ElkEdge[] = [];
  for (const wire of renderList.wires) {
    if (!wire.sourceId || !wire.targetId) {
      continue;
    }
    edges.push({
      id: wire.id,
      sources: [wire.sourceId],
      targets: [wire.targetId]
    });
  }

  return {
    id: 'root',
    children,
    edges,
    layoutOptions: elkPortLayoutOptions()
  };
}

function readNumber(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function collectEdgePoints(edge: ElkEdge): Array<{ x: number; y: number }> {
  const points: Array<{ x: number; y: number }> = [];
  const sections = Array.isArray(edge.sections) ? edge.sections : [];
  for (const section of sections) {
    if (section.startPoint) {
      points.push({ x: section.startPoint.x, y: section.startPoint.y });
    }
    if (Array.isArray(section.bendPoints)) {
      for (const bp of section.bendPoints) {
        points.push({ x: bp.x, y: bp.y });
      }
    }
    if (section.endPoint) {
      points.push({ x: section.endPoint.x, y: section.endPoint.y });
    }
  }
  return points;
}

function isRenderWire(value: unknown): value is RenderWire {
  const record = asRecord(value);
  return !!record && typeof record.sourceId === 'string' && typeof record.targetId === 'string';
}

function isRenderPin(value: unknown): value is RenderPin {
  const record = asRecord(value);
  return !!record && typeof record.symbolId === 'string';
}

function mapChildren(elkResult: ElkResult): Map<string, ElkNode> {
  const mapped = new Map<string, ElkNode>();
  const children = Array.isArray(elkResult.children) ? elkResult.children : [];
  for (const child of children) {
    const childRecord = asRecord(child);
    if (!childRecord) {
      continue;
    }
    const id = String(childRecord.id || '').trim();
    if (!id) {
      continue;
    }
    mapped.set(id, child as ElkNode);
  }
  return mapped;
}

export function applyElkResult(renderList: RenderList, elkResult: ElkResult): void {
  if (!elkResult || !Array.isArray(elkResult.children)) {
    return;
  }

  const childById = mapChildren(elkResult);

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
      const pinCandidate = renderList.byId.get(String(port.id || ''));
      if (!isRenderPin(pinCandidate)) {
        continue;
      }
      const pw = readNumber(port.width, pinCandidate.width || 14);
      const ph = readNumber(port.height, pinCandidate.height || 10);
      pinCandidate.x = readNumber(node.x, 0) + readNumber(port.x, 0) + pw * 0.5;
      pinCandidate.y = readNumber(node.y, 0) + readNumber(port.y, 0) + ph * 0.5;
    }
  }

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

  if (!Array.isArray(elkResult.edges)) {
    return;
  }

  for (const edge of elkResult.edges) {
    const wireCandidate = renderList.byId.get(String(edge.id || ''));
    if (!isRenderWire(wireCandidate)) {
      continue;
    }
    const points = collectEdgePoints(edge);
    if (points.length >= 2) {
      wireCandidate.bendPoints = points;
    }
  }
}

export async function runElkLayout(
  renderList: RenderList,
  ELK: ElkCtor | unknown
): Promise<{ engine: 'missing' | 'none' | 'elk' | 'error' }> {
  if (!renderList || typeof ELK !== 'function') {
    return { engine: 'missing' };
  }

  try {
    const graph = buildElkGraph(renderList);
    const elk = new (ELK as ElkCtor)();
    const result = await elk.layout(graph);
    if (!result || !Array.isArray(result.children)) {
      return { engine: 'none' };
    }
    applyElkResult(renderList, result);
    return { engine: 'elk' };
  } catch {
    return { engine: 'error' };
  }
}
