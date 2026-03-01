// Symbol shape library for the RTL schematic renderer.
// Each shape has draw(ctx, cx, cy, w, h, state) and boundingBox(cx, cy, w, h).

interface SymbolState {
  bus?: boolean;
}

interface BoundingBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

interface SymbolShape {
  draw: (
    ctx: CanvasRenderingContext2D,
    cx: number,
    cy: number,
    w: number,
    h: number,
    state: SymbolState
  ) => void;
  boundingBox: (cx: number, cy: number, w: number, h: number) => BoundingBox;
}

export const SYMBOL_TYPES = ['component', 'focus', 'io', 'memory', 'op', 'net', 'pin'] as const;

const CORNER_RADIUS = 6;
const SMALL_RADIUS = 3;

function roundedRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  w: number,
  h: number,
  r: number
): void {
  const radius = Math.min(r, w / 2, h / 2);
  ctx.beginPath();
  ctx.moveTo(x + radius, y);
  ctx.lineTo(x + w - radius, y);
  ctx.arcTo(x + w, y, x + w, y + radius, radius);
  ctx.lineTo(x + w, y + h - radius);
  ctx.arcTo(x + w, y + h, x + w - radius, y + h, radius);
  ctx.lineTo(x + radius, y + h);
  ctx.arcTo(x, y + h, x, y + h - radius, radius);
  ctx.lineTo(x, y + radius);
  ctx.arcTo(x, y, x + radius, y, radius);
  ctx.closePath();
}

function bb(cx: number, cy: number, w: number, h: number): BoundingBox {
  return { x: cx - w / 2, y: cy - h / 2, w, h };
}

export const symbolShapes = new Map<string, SymbolShape>();

// Component: rounded rectangle.
symbolShapes.set('component', {
  draw(ctx, cx, cy, w, h) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, CORNER_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.7;
    ctx.stroke();
  },
  boundingBox: bb
});

// Focus: rounded rectangle with thicker border.
symbolShapes.set('focus', {
  draw(ctx, cx, cy, w, h) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, CORNER_RADIUS);
    ctx.fill();
    ctx.lineWidth = 2.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// IO: small rounded rectangle.
symbolShapes.set('io', {
  draw(ctx, cx, cy, w, h) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, SMALL_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// Memory: double-border rounded rectangle.
symbolShapes.set('memory', {
  draw(ctx, cx, cy, w, h) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, CORNER_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();

    const inset = 3;
    roundedRect(ctx, x + inset, y + inset, w - inset * 2, h - inset * 2, CORNER_RADIUS - 1);
    ctx.stroke();
  },
  boundingBox: bb
});

// Op: rounded rectangle.
symbolShapes.set('op', {
  draw(ctx, cx, cy, w, h) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, SMALL_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// Net: compact rounded rectangle.
symbolShapes.set('net', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, SMALL_RADIUS);
    ctx.fill();
    ctx.lineWidth = state.bus ? 2.2 : 1.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// Pin: small rounded rectangle marker.
symbolShapes.set('pin', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, 2);
    ctx.fill();
    ctx.lineWidth = state.bus ? 2.1 : 1.2;
    ctx.stroke();
  },
  boundingBox: bb
});
