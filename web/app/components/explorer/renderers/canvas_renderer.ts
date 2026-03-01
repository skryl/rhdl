// Canvas 2D renderer for RTL schematic RenderList.

import { symbolShapes } from './symbols';
import { drawLegend, resolveWireStrokeWidth } from './themes';
import type {
  GraphViewport,
  RenderList,
  RenderNet,
  RenderPin,
  RenderSymbol,
  RenderWire,
  ThemePalette
} from '../lib/types';

interface CanvasLike {
  width: number;
  height: number;
  getContext: (type: '2d') => CanvasRenderingContext2D | null;
}

interface SymbolColors {
  fill: string;
  stroke: string;
  text: string;
  lineWidth: number;
}

interface WireColors {
  color: string;
  width: number;
}

interface NetColors {
  fill: string;
  stroke: string;
  text: string;
  lineWidth: number;
}

interface PinColors {
  fill: string;
  stroke: string;
  lineWidth: number;
}

function resolveColors(element: RenderSymbol, palette: ThemePalette): SymbolColors {
  const type = element.type || '';
  let fill = palette.componentBg;
  let stroke = palette.componentBorder;
  let text = palette.componentText;
  let lineWidth = 1.2;

  if (type === 'focus' || type === 'component') {
    fill = palette.componentBg;
    stroke = palette.componentBorder;
    lineWidth = type === 'focus' ? 2.2 : 1.7;
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

  return { fill, stroke, text, lineWidth };
}

function resolveWireColor(wire: RenderWire, palette: ThemePalette): WireColors {
  if (wire.selected) return { color: '#ffffff', width: 3.2 };
  if (wire.toggled) return { color: palette.wireToggle, width: 2.7 };
  if (wire.active) return { color: palette.wireActive, width: 2.0 };
  return { color: palette.wire, width: wire.bus ? 2.4 : 1.4 };
}

function resolveNetColors(net: RenderNet, palette: ThemePalette): NetColors {
  let fill = palette.netBg;
  let stroke = palette.netBorder;
  let text = palette.netText;
  let lineWidth = net.bus ? 2.2 : 1.2;

  if (net.selected) {
    stroke = palette.selected;
    lineWidth = 2.8;
  } else if (net.toggled) {
    stroke = palette.wireToggle;
    lineWidth = 2.2;
  } else if (net.active) {
    fill = palette.wireActive;
    stroke = palette.wireActive;
    text = '#001513';
  }

  return { fill, stroke, text, lineWidth };
}

function resolvePinColors(pin: RenderPin, palette: ThemePalette): PinColors {
  let fill = palette.pinBg;
  let stroke = palette.pinBorder;
  let lineWidth = pin.bus ? 2.1 : 1.2;

  if (pin.selected) {
    stroke = palette.selected;
    lineWidth = 2.4;
  } else if (pin.toggled) {
    stroke = palette.wireToggle;
  } else if (pin.active) {
    fill = palette.wireActive;
    stroke = palette.wireActive;
  }

  return { fill, stroke, lineWidth };
}

function resolveViewport(viewport: GraphViewport | null | undefined): GraphViewport {
  return {
    scale: Number.isFinite(viewport?.scale) ? (viewport?.scale || 1) : 1,
    x: Number.isFinite(viewport?.x) ? (viewport?.x || 0) : 0,
    y: Number.isFinite(viewport?.y) ? (viewport?.y || 0) : 0
  };
}

function hasPoint(value: unknown): value is { x: number; y: number } {
  if (!value || typeof value !== 'object') {
    return false;
  }
  const record = value as { x?: unknown; y?: unknown };
  return Number.isFinite(Number(record.x)) && Number.isFinite(Number(record.y));
}

export function createCanvasRenderer(canvas: CanvasLike) {
  const ctx = canvas.getContext('2d');
  let destroyed = false;

  function render(renderList: RenderList, viewport: GraphViewport, palette: ThemePalette): void {
    if (destroyed || !ctx) {
      return;
    }

    const resolvedViewport = resolveViewport(viewport);
    const scale = resolvedViewport.scale;
    const tx = resolvedViewport.x;
    const ty = resolvedViewport.y;

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(scale, 0, 0, scale, tx, ty);

    // 1. Draw wires (back layer).
    for (const wire of renderList.wires) {
      const wc = resolveWireColor(wire, palette);
      ctx.strokeStyle = wc.color;
      ctx.lineWidth = resolveWireStrokeWidth(wc.width, scale);
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';

      if (wire.bidir) {
        ctx.setLineDash([4, 3]);
      }

      ctx.beginPath();

      if (Array.isArray(wire.bendPoints) && wire.bendPoints.length >= 2) {
        ctx.moveTo(wire.bendPoints[0].x, wire.bendPoints[0].y);
        for (let index = 1; index < wire.bendPoints.length; index += 1) {
          ctx.lineTo(wire.bendPoints[index].x, wire.bendPoints[index].y);
        }
      } else {
        const src = renderList.byId.get(String(wire.sourceId || ''));
        const tgt = renderList.byId.get(String(wire.targetId || ''));
        if (!hasPoint(src) || !hasPoint(tgt)) {
          ctx.setLineDash([]);
          continue;
        }
        ctx.moveTo(src.x, src.y);
        ctx.lineTo(tgt.x, tgt.y);
      }

      ctx.stroke();

      if (wire.bidir) {
        ctx.setLineDash([]);
      }
    }

    // 2. Draw symbols.
    for (const sym of renderList.symbols) {
      const colors = resolveColors(sym, palette);
      const shape = symbolShapes.get(String(sym.type || '')) || symbolShapes.get('component');
      if (!shape) {
        continue;
      }

      ctx.fillStyle = colors.fill;
      ctx.strokeStyle = colors.stroke;
      shape.draw(
        ctx,
        Number(sym.x) || 0,
        Number(sym.y) || 0,
        Number(sym.width) || 150,
        Number(sym.height) || 64,
        {}
      );

      ctx.fillStyle = colors.text;
      ctx.font = '8px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(sym.label || ''), Number(sym.x) || 0, Number(sym.y) || 0);
    }

    // 3. Draw nets.
    for (const net of renderList.nets) {
      const colors = resolveNetColors(net, palette);
      const shape = symbolShapes.get('net');
      if (!shape) {
        continue;
      }

      ctx.fillStyle = colors.fill;
      ctx.strokeStyle = colors.stroke;
      ctx.lineWidth = colors.lineWidth;
      shape.draw(
        ctx,
        Number(net.x) || 0,
        Number(net.y) || 0,
        Number(net.width) || 52,
        Number(net.height) || 18,
        net
      );

      ctx.fillStyle = colors.text;
      ctx.font = '7px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(String(net.label || ''), Number(net.x) || 0, Number(net.y) || 0);
    }

    // 4. Draw pins.
    for (const pin of renderList.pins) {
      const colors = resolvePinColors(pin, palette);
      const shape = symbolShapes.get('pin');
      if (!shape) {
        continue;
      }

      ctx.fillStyle = colors.fill;
      ctx.strokeStyle = colors.stroke;
      ctx.lineWidth = colors.lineWidth;
      shape.draw(
        ctx,
        Number(pin.x) || 0,
        Number(pin.y) || 0,
        Number(pin.width) || 14,
        Number(pin.height) || 10,
        pin
      );
    }

    // Reset transform and draw legend in screen space.
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    drawLegend(ctx, canvas.width, canvas.height, palette);
  }

  function destroy(): void {
    destroyed = true;
  }

  return { render, destroy };
}
