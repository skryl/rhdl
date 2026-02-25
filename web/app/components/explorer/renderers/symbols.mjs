// Symbol shape library for the RTL schematic renderer.
// Each shape has draw(ctx, cx, cy, w, h, state) and boundingBox(cx, cy, w, h).

export const SYMBOL_TYPES = ['component', 'focus', 'io', 'memory', 'op', 'net', 'pin'];

const CORNER_RADIUS = 6;
const SMALL_RADIUS = 3;

function roundedRect(ctx, x, y, w, h, r) {
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

function bb(cx, cy, w, h) {
  return { x: cx - w / 2, y: cy - h / 2, w, h };
}

export const symbolShapes = new Map();

// component: rounded rectangle
symbolShapes.set('component', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, CORNER_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.7;
    ctx.stroke();
  },
  boundingBox: bb
});

// focus: rounded rectangle with thicker border
symbolShapes.set('focus', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, CORNER_RADIUS);
    ctx.fill();
    ctx.lineWidth = 2.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// io: small rounded rectangle
symbolShapes.set('io', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, SMALL_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// memory: double-border rounded rectangle
symbolShapes.set('memory', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    // outer border
    roundedRect(ctx, x, y, w, h, CORNER_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();
    // inner border (3px inset)
    const inset = 3;
    roundedRect(ctx, x + inset, y + inset, w - inset * 2, h - inset * 2, CORNER_RADIUS - 1);
    ctx.stroke();
  },
  boundingBox: bb
});

// op: rounded rectangle
symbolShapes.set('op', {
  draw(ctx, cx, cy, w, h, state) {
    const x = cx - w / 2;
    const y = cy - h / 2;
    roundedRect(ctx, x, y, w, h, SMALL_RADIUS);
    ctx.fill();
    ctx.lineWidth = 1.2;
    ctx.stroke();
  },
  boundingBox: bb
});

// net: compact rounded rectangle
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

// pin: small rounded rectangle marker
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
