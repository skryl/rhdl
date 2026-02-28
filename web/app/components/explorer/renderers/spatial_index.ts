// Spatial index for hit testing schematic elements.
// Uses simple array scan with priority ordering.
// Priority: pins > nets > symbols (topmost visual layer wins).

function contains(cx: any, cy: any, w: any, h: any, px: any, py: any) {
  const halfW = w / 2;
  const halfH = h / 2;
  return px >= cx - halfW && px <= cx + halfW && py >= cy - halfH && py <= cy + halfH;
}

export function buildSpatialIndex(renderList: any) {
  // Build entries sorted by priority: pins first, then nets, then symbols.
  const entries: any[] = [];

  for (const pin of renderList.pins) {
    entries.push({ priority: 0, element: pin });
  }
  for (const net of renderList.nets) {
    entries.push({ priority: 1, element: net });
  }
  for (const sym of renderList.symbols) {
    entries.push({ priority: 2, element: sym });
  }

  function queryPoint(px: any, py: any) {
    let bestHit = null;
    let bestPriority = Infinity;

    for (const entry of entries) {
      const el = entry.element;
      const w = el.width || 14;
      const h = el.height || 10;
      if (contains(el.x, el.y, w, h, px, py)) {
        if (entry.priority < bestPriority) {
          bestPriority = entry.priority;
          bestHit = el;
        }
      }
    }

    return bestHit;
  }

  return { queryPoint };
}
