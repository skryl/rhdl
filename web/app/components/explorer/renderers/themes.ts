// Renderer-agnostic theme system.

export function getThemePalette(theme = 'shenzhen') {
  if (theme === 'shenzhen') {
    return {
      componentBg: '#143848',
      componentBorder: '#4ec8d8',
      componentText: '#d4eef5',
      pinBg: '#2d4040',
      pinBorder: '#78a898',
      netBg: '#1e3828',
      netBorder: '#58a068',
      netText: '#b0d4b8',
      ioBg: '#2e2850',
      ioBorder: '#9088e0',
      ioText: '#d8d8f0',
      opBg: '#453820',
      opBorder: '#d4a850',
      opText: '#f0e4c8',
      memoryBg: '#4a3020',
      memoryBorder: '#d08848',
      wire: '#4a7868',
      wireActive: '#7be9ad',
      wireToggle: '#f4bf66',
      selected: '#9cffe3'
    };
  }

  // original theme
  return {
    componentBg: '#214c71',
    componentBorder: '#2f6b97',
    componentText: '#e7f3ff',
    pinBg: '#35597a',
    pinBorder: '#79bde3',
    netBg: '#223247',
    netBorder: '#3e5f83',
    netText: '#c0d7ef',
    ioBg: '#2a2850',
    ioBorder: '#8080d4',
    ioText: '#d4d4f0',
    opBg: '#4a4030',
    opBorder: '#c8a050',
    opText: '#f0e0c0',
    memoryBg: '#54434e',
    memoryBorder: '#c08068',
    wire: '#3a5f82',
    wireActive: '#3dd7c2',
    wireToggle: '#ffbc5a',
    selected: '#7fdfff'
  };
}

const WIRE_ZOOM_WIDTH_EXPONENT = 0.65;
const MIN_WIRE_ZOOM_FACTOR = 0.18;

export function resolveWireStrokeWidth(strokeWidth, viewportScale = 1) {
  const base = Number(strokeWidth);
  if (!Number.isFinite(base) || base <= 0) {
    return 0;
  }
  const scale = Number(viewportScale);
  if (!Number.isFinite(scale) || scale >= 1) {
    return base;
  }
  if (scale <= 0) {
    return base * MIN_WIRE_ZOOM_FACTOR;
  }
  const zoomFactor = Math.max(MIN_WIRE_ZOOM_FACTOR, Math.pow(scale, WIRE_ZOOM_WIDTH_EXPONENT));
  return base * zoomFactor;
}

export function resolveElementColors(element, palette, options = {}) {
  const type = element.type || '';
  const viewportScale = Number(options.viewportScale);
  const wireStrokeWidth = (rawWidth) => resolveWireStrokeWidth(rawWidth, viewportScale);

  // Wire
  if (type === 'wire') {
    if (element.selected) return { stroke: '#ffffff', strokeWidth: wireStrokeWidth(3.2) };
    if (element.toggled) return { stroke: palette.wireToggle, strokeWidth: wireStrokeWidth(2.7) };
    if (element.active) return { stroke: palette.wireActive, strokeWidth: wireStrokeWidth(2.0) };
    return { stroke: palette.wire, strokeWidth: wireStrokeWidth(element.bus ? 2.4 : 1.4) };
  }

  // Net
  if (type === 'net') {
    let fill = palette.netBg;
    let stroke = palette.netBorder;
    let text = palette.netText;
    let strokeWidth = element.bus ? 2.2 : 1.2;

    if (element.selected) {
      stroke = palette.selected;
      strokeWidth = 2.8;
    } else if (element.toggled) {
      stroke = palette.wireToggle;
      strokeWidth = 2.2;
    } else if (element.active) {
      fill = palette.wireActive;
      stroke = palette.wireActive;
      text = '#001513';
    }

    return { fill, stroke, text, strokeWidth };
  }

  // Pin
  if (type === 'pin') {
    let fill = palette.pinBg;
    let stroke = palette.pinBorder;
    let strokeWidth = element.bus ? 2.1 : 1.2;

    if (element.selected) {
      stroke = palette.selected;
      strokeWidth = 2.4;
    } else if (element.toggled) {
      stroke = palette.wireToggle;
    } else if (element.active) {
      fill = palette.wireActive;
      stroke = palette.wireActive;
    }

    return { fill, stroke, strokeWidth };
  }

  // Symbol types: focus, component, memory, op, io
  let fill = palette.componentBg;
  let stroke = palette.componentBorder;
  let text = palette.componentText;
  let strokeWidth = 1.7;

  if (type === 'focus') {
    strokeWidth = 2.2;
  } else if (type === 'memory') {
    fill = palette.memoryBg;
    stroke = palette.memoryBorder || palette.wire;
  } else if (type === 'op') {
    fill = palette.opBg;
    stroke = palette.opBorder || palette.wire;
    text = palette.opText || text;
  } else if (type === 'io') {
    fill = palette.ioBg;
    stroke = palette.ioBorder;
    text = palette.ioText || text;
  }

  return { fill, stroke, text, strokeWidth };
}

export function getLegendEntries(palette) {
  return [
    { label: 'Component', fill: palette.componentBg, stroke: palette.componentBorder },
    { label: 'IO Port', fill: palette.ioBg, stroke: palette.ioBorder },
    { label: 'Op / Assign', fill: palette.opBg, stroke: palette.opBorder || palette.wire },
    { label: 'Memory', fill: palette.memoryBg, stroke: palette.memoryBorder || palette.wire },
    { label: 'Net / Signal', fill: palette.netBg, stroke: palette.netBorder },
    { label: 'Pin', fill: palette.pinBg, stroke: palette.pinBorder },
    { label: 'Wire', fill: null, stroke: palette.wire, isLine: true }
  ];
}

export function drawLegend(ctx, canvasWidth, canvasHeight, palette) {
  const entries = getLegendEntries(palette);
  const fontSize = 11;
  const swatchW = 18;
  const swatchH = 12;
  const rowH = 20;
  const pad = 12;
  const gap = 6;
  const textOffsetX = swatchW + gap;

  ctx.font = `${fontSize}px monospace`;
  let maxTextW = 0;
  for (const e of entries) {
    const w = ctx.measureText(e.label).width;
    if (w > maxTextW) maxTextW = w;
  }

  const boxW = pad * 2 + textOffsetX + maxTextW;
  const boxH = pad * 2 + entries.length * rowH - (rowH - swatchH);
  const boxX = canvasWidth - boxW - 14;
  const boxY = canvasHeight - boxH - 14;

  // Background
  ctx.fillStyle = 'rgba(0, 12, 10, 0.82)';
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  const r = 4;
  ctx.moveTo(boxX + r, boxY);
  ctx.lineTo(boxX + boxW - r, boxY);
  ctx.arcTo(boxX + boxW, boxY, boxX + boxW, boxY + r, r);
  ctx.lineTo(boxX + boxW, boxY + boxH - r);
  ctx.arcTo(boxX + boxW, boxY + boxH, boxX + boxW - r, boxY + boxH, r);
  ctx.lineTo(boxX + r, boxY + boxH);
  ctx.arcTo(boxX, boxY + boxH, boxX, boxY + boxH - r, r);
  ctx.lineTo(boxX, boxY + r);
  ctx.arcTo(boxX, boxY, boxX + r, boxY, r);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Entries
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    const sx = boxX + pad;
    const sy = boxY + pad + i * rowH;

    if (e.isLine) {
      // Draw a line swatch
      ctx.strokeStyle = e.stroke;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(sx, sy + swatchH / 2);
      ctx.lineTo(sx + swatchW, sy + swatchH / 2);
      ctx.stroke();
    } else {
      // Draw a filled rect swatch
      ctx.fillStyle = e.fill;
      ctx.strokeStyle = e.stroke;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.rect(sx, sy, swatchW, swatchH);
      ctx.fill();
      ctx.stroke();
    }

    // Label
    ctx.fillStyle = 'rgba(220, 230, 225, 0.9)';
    ctx.font = `${fontSize}px monospace`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(e.label, sx + textOffsetX, sy + swatchH / 2);
  }
}
