function elkPortLayoutOptions() {
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

function toElkPortSide(side) {
  const raw = String(side || '').toLowerCase();
  if (raw === 'left') {
    return 'WEST';
  }
  if (raw === 'right') {
    return 'EAST';
  }
  if (raw === 'top') {
    return 'NORTH';
  }
  if (raw === 'bottom') {
    return 'SOUTH';
  }
  return 'WEST';
}

export async function runElkPortLayout({ cy, state } = {}) {
  if (!cy || !state || typeof window.ELK !== 'function') {
    if (state?.components) {
      state.components.graphLayoutEngine = 'none';
    }
    return;
  }

  const symbolNodes = cy.nodes('.schem-symbol');
  const netNodes = cy.nodes('.schem-net');
  const pinNodes = cy.nodes('.schem-pin');
  const wireEdges = cy.edges('.schem-wire');
  if (symbolNodes.length === 0 && netNodes.length === 0) {
    state.components.graphLayoutEngine = 'none';
    return;
  }

  const pinBySymbol = new Map();
  pinNodes.forEach((pin) => {
    const symbolId = String(pin.data('symbolId') || '').trim();
    if (!symbolId) {
      return;
    }
    if (!pinBySymbol.has(symbolId)) {
      pinBySymbol.set(symbolId, []);
    }
    pinBySymbol.get(symbolId).push(pin);
  });

  const children = [];
  symbolNodes.forEach((symbol) => {
    const symbolId = symbol.id();
    const width = Math.max(92, Number.parseInt(symbol.data('symbolWidth'), 10) || symbol.outerWidth() || 150);
    const height = Math.max(36, Number.parseInt(symbol.data('symbolHeight'), 10) || symbol.outerHeight() || 64);
    const ports = (pinBySymbol.get(symbolId) || []).map((pin) => ({
      id: pin.id(),
      width: Math.max(8, pin.outerWidth() || 12),
      height: Math.max(6, pin.outerHeight() || 8),
      layoutOptions: {
        'elk.port.side': toElkPortSide(pin.data('side')),
        'elk.port.index': String(Number.parseInt(pin.data('order'), 10) || 0)
      }
    }));

    children.push({
      id: symbolId,
      width,
      height,
      ports,
      layoutOptions: {
        'elk.portConstraints': 'FIXED_SIDE'
      }
    });
  });

  netNodes.forEach((net) => {
    const width = Math.max(26, net.outerWidth() || 52);
    const height = Math.max(12, net.outerHeight() || 18);
    children.push({
      id: net.id(),
      width,
      height
    });
  });

  const edges = [];
  wireEdges.forEach((edge) => {
    const source = edge.source();
    const target = edge.target();
    const sourceId = source.id();
    const targetId = target.id();
    if (!sourceId || !targetId) {
      return;
    }
    edges.push({
      id: edge.id(),
      sources: [sourceId],
      targets: [targetId]
    });
  });

  const elk = new window.ELK();
  const graph = {
    id: 'root',
    children,
    edges,
    layoutOptions: elkPortLayoutOptions()
  };

  const laidOut = await elk.layout(graph);
  if (!laidOut || !Array.isArray(laidOut.children)) {
    state.components.graphLayoutEngine = 'none';
    return;
  }
  if (cy !== state.components.graph) {
    return;
  }

  const childById = new Map(laidOut.children.map((entry) => [String(entry.id || ''), entry]));
  cy.batch(() => {
    symbolNodes.forEach((symbol) => {
      const node = childById.get(symbol.id());
      if (!node) {
        return;
      }
      const width = Number(node.width) || Math.max(92, Number.parseInt(symbol.data('symbolWidth'), 10) || symbol.outerWidth() || 150);
      const height = Number(node.height) || Math.max(36, Number.parseInt(symbol.data('symbolHeight'), 10) || symbol.outerHeight() || 64);
      const x = (Number(node.x) || 0) + width * 0.5;
      const y = (Number(node.y) || 0) + height * 0.5;
      symbol.position({ x, y });

      const ports = Array.isArray(node.ports) ? node.ports : [];
      for (const port of ports) {
        const pin = cy.getElementById(String(port.id || ''));
        if (!pin || pin.length === 0) {
          continue;
        }
        const px = (Number(node.x) || 0) + (Number(port.x) || 0) + (Number(port.width) || pin.outerWidth() || 12) * 0.5;
        const py = (Number(node.y) || 0) + (Number(port.y) || 0) + (Number(port.height) || pin.outerHeight() || 8) * 0.5;
        pin.position({ x: px, y: py });
      }
    });

    netNodes.forEach((net) => {
      const node = childById.get(net.id());
      if (!node) {
        return;
      }
      const width = Number(node.width) || net.outerWidth() || 52;
      const height = Number(node.height) || net.outerHeight() || 18;
      const x = (Number(node.x) || 0) + width * 0.5;
      const y = (Number(node.y) || 0) + height * 0.5;
      net.position({ x, y });
    });
  });

  state.components.graphLayoutEngine = 'elk';
  cy.fit(cy.elements(), 26);
}
