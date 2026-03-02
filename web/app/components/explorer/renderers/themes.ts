// Renderer-agnostic theme system.

import { asRecord, type ElementColorResult, type ThemePalette } from '../lib/types';

interface ElementColorOptions {
  viewportScale?: number;
}

interface LegendEntry {
  label: string;
  fill: string | null;
  stroke: string;
  isLine?: boolean;
}

export function getThemePalette(theme = 'shenzhen'): ThemePalette {
  if (theme === 'shenzhen') {
    return {
      componentBg: '#1b3d32',
      componentBorder: '#76d4a4',
      componentText: '#d8eee0',
      pinBg: '#2d5d4f',
      pinBorder: '#78a898',
      netBg: '#243a35',
      netBorder: '#58a068',
      netText: '#b0d4b8',
      ioBg: '#28463d',
      ioBorder: '#9088e0',
      ioText: '#d8d8f0',
      opBg: '#3f4c3a',
      opBorder: '#d4a850',
      opText: '#f0e4c8',
      memoryBg: '#4f3e2f',
      memoryBorder: '#d08848',
      wire: '#4f7d6d',
      wireActive: '#7be9ad',
      wireToggle: '#f4bf66',
      selected: '#9cffe3'
    };
  }

  // Original theme.
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

export function resolveWireStrokeWidth(strokeWidth: unknown, viewportScale = 1): number {
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

export function resolveElementColors(
  element: unknown,
  palette: ThemePalette,
  options: ElementColorOptions = {}
): ElementColorResult {
  const elementRecord = asRecord(element) || {};
  const type = String(elementRecord.type || '');
  const viewportScale = Number(options.viewportScale);
  const wireStrokeWidth = (rawWidth: unknown) =>
    resolveWireStrokeWidth(rawWidth, Number.isFinite(viewportScale) ? viewportScale : 1);

  // Wire
  if (type === 'wire') {
    if (elementRecord.selected === true) return { stroke: '#ffffff', strokeWidth: wireStrokeWidth(3.2) };
    if (elementRecord.toggled === true) return { stroke: palette.wireToggle, strokeWidth: wireStrokeWidth(2.7) };
    if (elementRecord.active === true) return { stroke: palette.wireActive, strokeWidth: wireStrokeWidth(2.0) };
    return {
      stroke: palette.wire,
      strokeWidth: wireStrokeWidth(elementRecord.bus === true ? 2.4 : 1.4)
    };
  }

  // Net
  if (type === 'net') {
    let fill = palette.netBg;
    let stroke = palette.netBorder;
    let text = palette.netText;
    let strokeWidth = elementRecord.bus === true ? 2.2 : 1.2;

    if (elementRecord.selected === true) {
      stroke = palette.selected;
      strokeWidth = 2.8;
    } else if (elementRecord.toggled === true) {
      stroke = palette.wireToggle;
      strokeWidth = 2.2;
    } else if (elementRecord.active === true) {
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
    let strokeWidth = elementRecord.bus === true ? 2.1 : 1.2;

    if (elementRecord.selected === true) {
      stroke = palette.selected;
      strokeWidth = 2.4;
    } else if (elementRecord.toggled === true) {
      stroke = palette.wireToggle;
    } else if (elementRecord.active === true) {
      fill = palette.wireActive;
      stroke = palette.wireActive;
    }

    return { fill, stroke, strokeWidth };
  }

  // Symbol types: focus, component, memory, op, io.
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

export function getLegendEntries(palette: ThemePalette): LegendEntry[] {
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

export function drawLegend(
  ctx: CanvasRenderingContext2D,
  canvasWidth: unknown,
  canvasHeight: unknown,
  palette: ThemePalette
): void {
  if (!ctx || typeof ctx.measureText !== 'function') {
    return;
  }

  const width = Number(canvasWidth);
  const height = Number(canvasHeight);
  const safeWidth = Number.isFinite(width) ? width : 0;
  const safeHeight = Number.isFinite(height) ? height : 0;

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
  for (const entry of entries) {
    const measure = ctx.measureText(entry.label).width;
    if (measure > maxTextW) {
      maxTextW = measure;
    }
  }

  const boxW = pad * 2 + textOffsetX + maxTextW;
  const boxH = pad * 2 + entries.length * rowH - (rowH - swatchH);
  const boxX = safeWidth - boxW - 14;
  const boxY = safeHeight - boxH - 14;

  // Background.
  ctx.fillStyle = 'rgba(0, 12, 10, 0.82)';
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.12)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  const radius = 4;
  ctx.moveTo(boxX + radius, boxY);
  ctx.lineTo(boxX + boxW - radius, boxY);
  ctx.arcTo(boxX + boxW, boxY, boxX + boxW, boxY + radius, radius);
  ctx.lineTo(boxX + boxW, boxY + boxH - radius);
  ctx.arcTo(boxX + boxW, boxY + boxH, boxX + boxW - radius, boxY + boxH, radius);
  ctx.lineTo(boxX + radius, boxY + boxH);
  ctx.arcTo(boxX, boxY + boxH, boxX, boxY + boxH - radius, radius);
  ctx.lineTo(boxX, boxY + radius);
  ctx.arcTo(boxX, boxY, boxX + radius, boxY, radius);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();

  // Entries.
  for (let index = 0; index < entries.length; index += 1) {
    const entry = entries[index];
    const sx = boxX + pad;
    const sy = boxY + pad + index * rowH;

    if (entry.isLine) {
      ctx.strokeStyle = entry.stroke;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(sx, sy + swatchH / 2);
      ctx.lineTo(sx + swatchW, sy + swatchH / 2);
      ctx.stroke();
    } else {
      ctx.fillStyle = entry.fill || 'transparent';
      ctx.strokeStyle = entry.stroke;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.rect(sx, sy, swatchW, swatchH);
      ctx.fill();
      ctx.stroke();
    }

    ctx.fillStyle = 'rgba(220, 230, 225, 0.9)';
    ctx.font = `${fontSize}px monospace`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(entry.label, sx + textOffsetX, sy + swatchH / 2);
  }
}
