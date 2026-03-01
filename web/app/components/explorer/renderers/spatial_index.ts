// Spatial index for hit testing schematic elements.
// Uses simple array scan with priority ordering.
// Priority: pins > nets > symbols (topmost visual layer wins).

import type { RenderList, RenderNet, RenderPin, RenderSymbol, SpatialIndex } from '../lib/types';

type HitElement = RenderPin | RenderNet | RenderSymbol;

interface IndexedEntry {
  priority: number;
  element: HitElement;
}

function contains(
  cx: number,
  cy: number,
  w: number,
  h: number,
  px: number,
  py: number
): boolean {
  const halfW = w / 2;
  const halfH = h / 2;
  return px >= cx - halfW && px <= cx + halfW && py >= cy - halfH && py <= cy + halfH;
}

export function buildSpatialIndex(renderList: RenderList): SpatialIndex {
  const entries: IndexedEntry[] = [];

  for (const pin of renderList.pins) {
    entries.push({ priority: 0, element: pin });
  }
  for (const net of renderList.nets) {
    entries.push({ priority: 1, element: net });
  }
  for (const sym of renderList.symbols) {
    entries.push({ priority: 2, element: sym });
  }

  function queryPoint(px: number, py: number): HitElement | null {
    let bestHit: HitElement | null = null;
    let bestPriority = Infinity;

    for (const entry of entries) {
      const el = entry.element;
      const x = Number(el.x) || 0;
      const y = Number(el.y) || 0;
      const w = Number(el.width) || 14;
      const h = Number(el.height) || 10;
      if (contains(x, y, w, h, px, py) && entry.priority < bestPriority) {
        bestPriority = entry.priority;
        bestHit = el;
      }
    }

    return bestHit;
  }

  return { queryPoint };
}
