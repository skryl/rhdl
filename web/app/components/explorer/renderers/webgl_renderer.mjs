// WebGL 2.0 renderer for RTL schematic RenderList.
// Uses instanced rendering for symbols/pins/nets and thick-line quads for wires.

import { RECT_VERTEX, RECT_FRAGMENT, LINE_VERTEX, LINE_FRAGMENT } from './webgl_shaders.mjs';
import { resolveElementColors } from './themes.mjs';

function parseHexColor(hex) {
  const h = String(hex || '#000000').replace('#', '');
  const r = parseInt(h.substring(0, 2), 16) / 255;
  const g = parseInt(h.substring(2, 4), 16) / 255;
  const b = parseInt(h.substring(4, 6), 16) / 255;
  return [r, g, b, 1.0];
}

function compileShader(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    const info = gl.getShaderInfoLog(shader);
    gl.deleteShader(shader);
    return null;
  }
  return shader;
}

function createProgram(gl, vsSource, fsSource) {
  const vs = compileShader(gl, gl.VERTEX_SHADER, vsSource);
  const fs = compileShader(gl, gl.FRAGMENT_SHADER, fsSource);
  if (!vs || !fs) return null;

  const program = gl.createProgram();
  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return null;
  }

  return program;
}

export function createWebGLRenderer(canvas) {
  const gl = canvas.getContext('webgl2');
  if (!gl) return null;

  // Build shader programs
  const rectProgram = createProgram(gl, RECT_VERTEX, RECT_FRAGMENT);
  const lineProgram = createProgram(gl, LINE_VERTEX, LINE_FRAGMENT);

  // Quad corners for instanced rect rendering (two triangles)
  const quadVerts = new Float32Array([
    0, 0,  1, 0,  0, 1,
    0, 1,  1, 0,  1, 1
  ]);
  const quadBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
  gl.bufferData(gl.ARRAY_BUFFER, quadVerts, gl.STATIC_DRAW);

  // Instance buffers (pre-allocated, grown as needed)
  const rectInstanceBuffer = gl.createBuffer();
  const lineVertexBuffer = gl.createBuffer();

  let destroyed = false;

  // Instance data layout per rect: position(2) + size(2) + fill(4) + stroke(4) + strokeWidth(1) + cornerRadius(1) = 14 floats
  const RECT_FLOATS = 14;
  // Line vertex data: start(2) + end(2) + color(4) + width(1) + vertexIndex(1) = 10 floats per vertex, 4 vertices per line
  const LINE_VERTEX_FLOATS = 10;

  function buildRectInstanceData(elements, palette, typeResolver) {
    const data = new Float32Array(elements.length * RECT_FLOATS);
    let offset = 0;
    for (const el of elements) {
      const colors = typeResolver(el, palette);
      const fill = parseHexColor(colors.fill || '#000000');
      const stroke = parseHexColor(colors.stroke || '#000000');

      data[offset++] = el.x;
      data[offset++] = el.y;
      data[offset++] = el.width || 100;
      data[offset++] = el.height || 50;
      data[offset++] = fill[0]; data[offset++] = fill[1]; data[offset++] = fill[2]; data[offset++] = fill[3];
      data[offset++] = stroke[0]; data[offset++] = stroke[1]; data[offset++] = stroke[2]; data[offset++] = stroke[3];
      data[offset++] = colors.strokeWidth || 1.2;
      data[offset++] = el.type === 'pin' ? 2 : (el.type === 'net' || el.type === 'io' || el.type === 'op') ? 3 : 6;
    }
    return data;
  }

  function buildLineData(wires, renderList, palette, viewportScale = 1) {
    // Count total line segments (each bend point pair = 1 segment, 4 vertices each)
    let totalSegments = 0;
    for (const wire of wires) {
      if (Array.isArray(wire.bendPoints) && wire.bendPoints.length >= 2) {
        totalSegments += wire.bendPoints.length - 1;
      } else {
        totalSegments += 1;
      }
    }

    const vertexData = new Float32Array(totalSegments * 4 * LINE_VERTEX_FLOATS);
    let vOffset = 0;

    for (const wire of wires) {
      const colors = resolveElementColors({ type: 'wire', ...wire }, palette, { viewportScale });
      const col = parseHexColor(colors.stroke || '#4f7d6d');
      const w = colors.strokeWidth || 1.4;

      if (Array.isArray(wire.bendPoints) && wire.bendPoints.length >= 2) {
        // Draw each segment of the polyline
        for (let s = 0; s < wire.bendPoints.length - 1; s++) {
          const p0 = wire.bendPoints[s];
          const p1 = wire.bendPoints[s + 1];
          for (let vi = 0; vi < 4; vi++) {
            vertexData[vOffset++] = p0.x;
            vertexData[vOffset++] = p0.y;
            vertexData[vOffset++] = p1.x;
            vertexData[vOffset++] = p1.y;
            vertexData[vOffset++] = col[0]; vertexData[vOffset++] = col[1]; vertexData[vOffset++] = col[2]; vertexData[vOffset++] = col[3];
            vertexData[vOffset++] = w;
            vertexData[vOffset++] = vi;
          }
        }
      } else {
        // Fallback: straight line between source and target
        const src = renderList.byId.get(wire.sourceId);
        const tgt = renderList.byId.get(wire.targetId);
        if (!src || !tgt) continue;
        for (let vi = 0; vi < 4; vi++) {
          vertexData[vOffset++] = src.x;
          vertexData[vOffset++] = src.y;
          vertexData[vOffset++] = tgt.x;
          vertexData[vOffset++] = tgt.y;
          vertexData[vOffset++] = col[0]; vertexData[vOffset++] = col[1]; vertexData[vOffset++] = col[2]; vertexData[vOffset++] = col[3];
          vertexData[vOffset++] = w;
          vertexData[vOffset++] = vi;
        }
      }
    }

    return vertexData.subarray(0, vOffset);
  }

  function render(renderList, viewport, palette) {
    if (destroyed || !gl) return;

    const { scale = 1, x: tx = 0, y: ty = 0 } = viewport || {};
    const width = gl.drawingBufferWidth || canvas.width;
    const height = gl.drawingBufferHeight || canvas.height;

    gl.viewport(0, 0, width, height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    // View matrix: [scale, 0, tx, 0, scale, ty, 0, 0, 1]
    const viewMatrix = new Float32Array([
      scale, 0, 0,
      0, scale, 0,
      tx, ty, 1
    ]);

    // --- Draw wires ---
    if (lineProgram && renderList.wires.length > 0) {
      gl.useProgram(lineProgram);

      const uView = gl.getUniformLocation(lineProgram, 'u_viewMatrix');
      const uRes = gl.getUniformLocation(lineProgram, 'u_resolution');
      gl.uniformMatrix3fv(uView, false, viewMatrix);
      gl.uniform2f(uRes, width, height);

      const lineData = buildLineData(renderList.wires, renderList, palette, scale);
      gl.bindBuffer(gl.ARRAY_BUFFER, lineVertexBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, lineData, gl.DYNAMIC_DRAW);

      const stride = LINE_VERTEX_FLOATS * 4;
      // a_start
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0);
      gl.vertexAttribDivisor(0, 0);
      // a_end
      gl.enableVertexAttribArray(1);
      gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8);
      gl.vertexAttribDivisor(1, 0);
      // a_color
      gl.enableVertexAttribArray(2);
      gl.vertexAttribPointer(2, 4, gl.FLOAT, false, stride, 16);
      gl.vertexAttribDivisor(2, 0);
      // a_width
      gl.enableVertexAttribArray(3);
      gl.vertexAttribPointer(3, 1, gl.FLOAT, false, stride, 32);
      gl.vertexAttribDivisor(3, 0);
      // a_vertexIndex
      gl.enableVertexAttribArray(4);
      gl.vertexAttribPointer(4, 1, gl.FLOAT, false, stride, 36);
      gl.vertexAttribDivisor(4, 0);

      const lineQuadCount = lineData.length / (4 * LINE_VERTEX_FLOATS);
      for (let i = 0; i < lineQuadCount; i++) {
        gl.drawArrays(gl.TRIANGLE_STRIP, i * 4, 4);
      }
    }

    // --- Draw rects (symbols, nets, pins) ---
    if (rectProgram) {
      gl.useProgram(rectProgram);

      const uView = gl.getUniformLocation(rectProgram, 'u_viewMatrix');
      const uRes = gl.getUniformLocation(rectProgram, 'u_resolution');
      gl.uniformMatrix3fv(uView, false, viewMatrix);
      gl.uniform2f(uRes, width, height);

      // All rect-like elements combined
      const allRects = [
        ...renderList.symbols.map(el => ({ ...el, type: el.type || 'component' })),
        ...renderList.nets.map(el => ({ ...el, type: 'net' })),
        ...renderList.pins.map(el => ({ ...el, type: 'pin' }))
      ];

      if (allRects.length > 0) {
        const instanceData = buildRectInstanceData(allRects, palette, resolveElementColors);

        // Quad corner attribute (per-vertex, non-instanced)
        gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
        gl.enableVertexAttribArray(6);
        gl.vertexAttribPointer(6, 2, gl.FLOAT, false, 0, 0);
        gl.vertexAttribDivisor(6, 0);

        // Instance attributes
        gl.bindBuffer(gl.ARRAY_BUFFER, rectInstanceBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, instanceData, gl.DYNAMIC_DRAW);

        const stride = RECT_FLOATS * 4;
        // a_position
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0);
        gl.vertexAttribDivisor(0, 1);
        // a_size
        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8);
        gl.vertexAttribDivisor(1, 1);
        // a_fillColor
        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, false, stride, 16);
        gl.vertexAttribDivisor(2, 1);
        // a_strokeColor
        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(3, 4, gl.FLOAT, false, stride, 32);
        gl.vertexAttribDivisor(3, 1);
        // a_strokeWidth
        gl.enableVertexAttribArray(4);
        gl.vertexAttribPointer(4, 1, gl.FLOAT, false, stride, 48);
        gl.vertexAttribDivisor(4, 1);
        // a_cornerRadius
        gl.enableVertexAttribArray(5);
        gl.vertexAttribPointer(5, 1, gl.FLOAT, false, stride, 52);
        gl.vertexAttribDivisor(5, 1);

        gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, allRects.length);
      }
    }
  }

  function destroy() {
    destroyed = true;
    if (rectProgram) gl.deleteProgram(rectProgram);
    if (lineProgram) gl.deleteProgram(lineProgram);
    if (quadBuffer) gl.deleteBuffer(quadBuffer);
    if (rectInstanceBuffer) gl.deleteBuffer(rectInstanceBuffer);
    if (lineVertexBuffer) gl.deleteBuffer(lineVertexBuffer);
  }

  return { render, destroy };
}
