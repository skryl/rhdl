// Canvas 2D renderer for RTL schematic RenderList.

import { symbolShapes } from './symbols.mjs';

function resolveColors(element, palette) {
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
    stroke = palette.wire;
  } else if (type === 'op') {
    fill = palette.opBg;
    stroke = palette.wire;
  } else if (type === 'io') {
    fill = palette.ioBg;
    stroke = palette.ioBorder;
  }

  return { fill, stroke, text, lineWidth };
}

function resolveWireColor(wire, palette) {
  if (wire.selected) return { color: '#ffffff', width: 3.2 };
  if (wire.toggled) return { color: palette.wireToggle, width: 2.7 };
  if (wire.active) return { color: palette.wireActive, width: 2.0 };
  return { color: palette.wire, width: wire.bus ? 2.4 : 1.4 };
}

function resolveNetColors(net, palette) {
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

function resolvePinColors(pin, palette) {
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

export function createCanvasRenderer(canvas) {
  const ctx = canvas.getContext('2d');
  let destroyed = false;

  function render(renderList, viewport, palette) {
    if (destroyed || !ctx) return;

    const { scale = 1, x: tx = 0, y: ty = 0 } = viewport || {};

    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.setTransform(scale, 0, 0, scale, tx, ty);

    // 1. Draw wires (back layer)
    for (const wire of renderList.wires) {
      const src = renderList.byId.get(wire.sourceId);
      const tgt = renderList.byId.get(wire.targetId);
      if (!src || !tgt) continue;

      const wc = resolveWireColor(wire, palette);
      ctx.strokeStyle = wc.color;
      ctx.lineWidth = wc.width;

      if (wire.bidir) {
        ctx.setLineDash([4, 3]);
      }

      ctx.beginPath();
      ctx.moveTo(src.x, src.y);
      ctx.lineTo(tgt.x, tgt.y);
      ctx.stroke();

      if (wire.bidir) {
        ctx.setLineDash([]);
      }
    }

    // 2. Draw symbols
    for (const sym of renderList.symbols) {
      const colors = resolveColors(sym, palette);
      const shape = symbolShapes.get(sym.type) || symbolShapes.get('component');

      ctx.fillStyle = colors.fill;
      ctx.strokeStyle = colors.stroke;
      shape.draw(ctx, sym.x, sym.y, sym.width, sym.height, sym);

      // label
      ctx.fillStyle = colors.text;
      ctx.font = '8px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(sym.label, sym.x, sym.y);
    }

    // 3. Draw nets
    for (const net of renderList.nets) {
      const colors = resolveNetColors(net, palette);
      const shape = symbolShapes.get('net');

      ctx.fillStyle = colors.fill;
      ctx.strokeStyle = colors.stroke;
      shape.draw(ctx, net.x, net.y, net.width, net.height, net);

      ctx.fillStyle = colors.text;
      ctx.font = '7px monospace';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(net.label, net.x, net.y);
    }

    // 4. Draw pins
    for (const pin of renderList.pins) {
      const colors = resolvePinColors(pin, palette);
      const shape = symbolShapes.get('pin');

      ctx.fillStyle = colors.fill;
      ctx.strokeStyle = colors.stroke;
      shape.draw(ctx, pin.x, pin.y, pin.width, pin.height, pin);
    }

    // reset transform
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  }

  function destroy() {
    destroyed = true;
  }

  return { render, destroy };
}
