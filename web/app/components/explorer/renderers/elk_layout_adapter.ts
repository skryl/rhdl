// ELK layout adapter for the RenderList.
// Builds an ELK graph from the RenderList, runs layout, and applies positions back.

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

export function toElkPortSide(side: any) {
  const raw = String(side || '').toLowerCase();
  if (raw === 'left') return 'WEST';
  if (raw === 'right') return 'EAST';
  if (raw === 'top') return 'NORTH';
  if (raw === 'bottom') return 'SOUTH';
  return 'WEST';
}

export function buildElkGraph(renderList: any) {
  const children = [];

  // Group pins by symbolId
  const pinsBySymbol = new Map();
  for (const pin of renderList.pins) {
    const sid = pin.symbolId;
    if (!sid) continue;
    if (!pinsBySymbol.has(sid)) pinsBySymbol.set(sid, []);
    pinsBySymbol.get(sid).push(pin);
  }

  // Symbols as children with ports
  for (const sym of renderList.symbols) {
    const ports = (pinsBySymbol.get(sym.id) || []).map((pin: any) => ({
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
    });
  }

  // Nets as children (no ports)
  for (const net of renderList.nets) {
    children.push({
      id: net.id,
      width: Math.max(26, net.width || 52),
      height: Math.max(12, net.height || 18)
    });
  }

  // Wires as edges
  const edges = [];
  for (const wire of renderList.wires) {
    if (!wire.sourceId || !wire.targetId) continue;
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

export function applyElkResult(renderList: any, elkResult: any) {
  if (!renderList || !elkResult || !Array.isArray(elkResult.children)) return;

  const childById = new Map();
  for (const child of elkResult.children) {
    childById.set(String(child.id || ''), child);
  }

  for (const sym of renderList.symbols) {
    const node = childById.get(sym.id);
    if (!node) continue;
    const w = Number(node.width) || sym.width;
    const h = Number(node.height) || sym.height;
    sym.x = (Number(node.x) || 0) + w * 0.5;
    sym.y = (Number(node.y) || 0) + h * 0.5;

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

  for (const net of renderList.nets) {
    const node = childById.get(net.id);
    if (!node) continue;
    const w = Number(node.width) || net.width || 52;
    const h = Number(node.height) || net.height || 18;
    net.x = (Number(node.x) || 0) + w * 0.5;
    net.y = (Number(node.y) || 0) + h * 0.5;
  }

  // Extract edge bend points from ELK edge sections onto wire objects
  if (Array.isArray(elkResult.edges)) {
    for (const edge of elkResult.edges) {
      const wire = renderList.byId.get(String(edge.id || ''));
      if (!wire) continue;
      const sections = edge.sections;
      if (!Array.isArray(sections) || sections.length === 0) continue;

      const points = [];
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

      if (points.length >= 2) {
        wire.bendPoints = points;
      }
    }
  }
}

export async function runElkLayout(renderList: any, ELK: any) {
  if (!renderList || typeof ELK !== 'function') {
    return { engine: 'missing' };
  }

  try {
    const graph = buildElkGraph(renderList);
    const elk = new ELK();
    const result = await elk.layout(graph);
    if (!result || !Array.isArray(result.children)) {
      return { engine: 'none' };
    }
    applyElkResult(renderList, result);
    return { engine: 'elk' };
  } catch (_err: any) {
    return { engine: 'error' };
  }
}
