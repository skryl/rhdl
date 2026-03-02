// WebGL 2.0 renderer for RTL schematic RenderList.
// Uses instanced rendering for symbols/pins/nets and thick-line quads for wires.

import { RECT_VERTEX, RECT_FRAGMENT, LINE_VERTEX, LINE_FRAGMENT } from './webgl_shaders';
import { resolveElementColors } from './themes';
import type {
  GraphViewport,
  RenderList,
  RenderNet,
  RenderPin,
  RenderSymbol,
  RenderWire,
  ThemePalette
} from '../lib/types';

type RectLike = (RenderSymbol & { type: string }) | (RenderNet & { type: 'net' }) | (RenderPin & { type: 'pin' });

interface WebGLCanvasLike {
  width: number;
  height: number;
  style?: unknown;
  getContext: (type: 'webgl2') => unknown;
}

function parseHexColor(hex: unknown): [number, number, number, number] {
  const raw = String(hex || '#000000').replace('#', '');
  const padded = raw.length >= 6 ? raw.slice(0, 6) : raw.padEnd(6, '0');
  const r = Number.parseInt(padded.slice(0, 2), 16) / 255;
  const g = Number.parseInt(padded.slice(2, 4), 16) / 255;
  const b = Number.parseInt(padded.slice(4, 6), 16) / 255;
  return [r, g, b, 1.0];
}

function compileShader(
  gl: WebGL2RenderingContext,
  type: number,
  source: string
): WebGLShader | null {
  const shader = gl.createShader(type);
  if (!shader) {
    return null;
  }

  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
    gl.deleteShader(shader);
    return null;
  }
  return shader;
}

function createProgram(
  gl: WebGL2RenderingContext,
  vsSource: string,
  fsSource: string
): WebGLProgram | null {
  const vs = compileShader(gl, gl.VERTEX_SHADER, vsSource);
  const fs = compileShader(gl, gl.FRAGMENT_SHADER, fsSource);
  if (!vs || !fs) {
    return null;
  }

  const program = gl.createProgram();
  if (!program) {
    return null;
  }

  gl.attachShader(program, vs);
  gl.attachShader(program, fs);
  gl.linkProgram(program);

  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
    gl.deleteProgram(program);
    return null;
  }

  return program;
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

function buildRectInstanceData(elements: RectLike[], palette: ThemePalette): Float32Array {
  const RECT_FLOATS = 14;
  const data = new Float32Array(elements.length * RECT_FLOATS);
  let offset = 0;

  for (const element of elements) {
    const colors = resolveElementColors(element, palette);
    const fill = parseHexColor(colors.fill || '#000000');
    const stroke = parseHexColor(colors.stroke || '#000000');

    data[offset++] = Number(element.x) || 0;
    data[offset++] = Number(element.y) || 0;
    data[offset++] = Number(element.width) || 100;
    data[offset++] = Number(element.height) || 50;

    data[offset++] = fill[0];
    data[offset++] = fill[1];
    data[offset++] = fill[2];
    data[offset++] = fill[3];

    data[offset++] = stroke[0];
    data[offset++] = stroke[1];
    data[offset++] = stroke[2];
    data[offset++] = stroke[3];

    data[offset++] = colors.strokeWidth || 1.2;
    data[offset++] = element.type === 'pin' ? 2 : (element.type === 'net' || element.type === 'io' || element.type === 'op') ? 3 : 6;
  }

  return data;
}

function buildLineData(
  wires: RenderWire[],
  renderList: RenderList,
  palette: ThemePalette,
  viewportScale = 1
): Float32Array {
  const LINE_VERTEX_FLOATS = 10;

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
    const colors = resolveElementColors({ ...wire, type: 'wire' }, palette, { viewportScale });
    const col = parseHexColor(colors.stroke || '#4f7d6d');
    const width = colors.strokeWidth || 1.4;

    if (Array.isArray(wire.bendPoints) && wire.bendPoints.length >= 2) {
      for (let segmentIndex = 0; segmentIndex < wire.bendPoints.length - 1; segmentIndex += 1) {
        const p0 = wire.bendPoints[segmentIndex];
        const p1 = wire.bendPoints[segmentIndex + 1];
        for (let vi = 0; vi < 4; vi += 1) {
          vertexData[vOffset++] = p0.x;
          vertexData[vOffset++] = p0.y;
          vertexData[vOffset++] = p1.x;
          vertexData[vOffset++] = p1.y;
          vertexData[vOffset++] = col[0];
          vertexData[vOffset++] = col[1];
          vertexData[vOffset++] = col[2];
          vertexData[vOffset++] = col[3];
          vertexData[vOffset++] = width;
          vertexData[vOffset++] = vi;
        }
      }
      continue;
    }

    const src = renderList.byId.get(String(wire.sourceId || ''));
    const tgt = renderList.byId.get(String(wire.targetId || ''));
    if (!hasPoint(src) || !hasPoint(tgt)) {
      continue;
    }

    for (let vi = 0; vi < 4; vi += 1) {
      vertexData[vOffset++] = src.x;
      vertexData[vOffset++] = src.y;
      vertexData[vOffset++] = tgt.x;
      vertexData[vOffset++] = tgt.y;
      vertexData[vOffset++] = col[0];
      vertexData[vOffset++] = col[1];
      vertexData[vOffset++] = col[2];
      vertexData[vOffset++] = col[3];
      vertexData[vOffset++] = width;
      vertexData[vOffset++] = vi;
    }
  }

  return vertexData.subarray(0, vOffset);
}

export function createWebGLRenderer(canvas: WebGLCanvasLike) {
  const glContext = canvas.getContext('webgl2') as WebGL2RenderingContext | null;
  if (!glContext) {
    return null;
  }
  const gl: WebGL2RenderingContext = glContext;

  const rectProgram = createProgram(gl, RECT_VERTEX, RECT_FRAGMENT);
  const lineProgram = createProgram(gl, LINE_VERTEX, LINE_FRAGMENT);

  const quadVerts = new Float32Array([
    0, 0, 1, 0, 0, 1,
    0, 1, 1, 0, 1, 1
  ]);
  const quadBuffer = gl.createBuffer();
  if (quadBuffer) {
    gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
    gl.bufferData(gl.ARRAY_BUFFER, quadVerts, gl.STATIC_DRAW);
  }

  const rectInstanceBuffer = gl.createBuffer();
  const lineVertexBuffer = gl.createBuffer();

  let destroyed = false;

  const RECT_FLOATS = 14;
  const LINE_VERTEX_FLOATS = 10;

  function render(renderList: RenderList, viewport: GraphViewport, palette: ThemePalette): void {
    if (destroyed) {
      return;
    }

    const resolvedViewport = resolveViewport(viewport);
    const width = gl.drawingBufferWidth || canvas.width;
    const height = gl.drawingBufferHeight || canvas.height;

    gl.viewport(0, 0, width, height);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    const viewMatrix = new Float32Array([
      resolvedViewport.scale, 0, 0,
      0, resolvedViewport.scale, 0,
      resolvedViewport.x, resolvedViewport.y, 1
    ]);

    // Draw wires.
    if (lineProgram && lineVertexBuffer && renderList.wires.length > 0) {
      gl.useProgram(lineProgram);

      const uView = gl.getUniformLocation(lineProgram, 'u_viewMatrix');
      const uRes = gl.getUniformLocation(lineProgram, 'u_resolution');
      gl.uniformMatrix3fv(uView, false, viewMatrix);
      gl.uniform2f(uRes, width, height);

      const lineData = buildLineData(renderList.wires, renderList, palette, resolvedViewport.scale);
      gl.bindBuffer(gl.ARRAY_BUFFER, lineVertexBuffer);
      gl.bufferData(gl.ARRAY_BUFFER, lineData, gl.DYNAMIC_DRAW);

      const stride = LINE_VERTEX_FLOATS * 4;
      gl.enableVertexAttribArray(0);
      gl.vertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0);
      gl.vertexAttribDivisor(0, 0);

      gl.enableVertexAttribArray(1);
      gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8);
      gl.vertexAttribDivisor(1, 0);

      gl.enableVertexAttribArray(2);
      gl.vertexAttribPointer(2, 4, gl.FLOAT, false, stride, 16);
      gl.vertexAttribDivisor(2, 0);

      gl.enableVertexAttribArray(3);
      gl.vertexAttribPointer(3, 1, gl.FLOAT, false, stride, 32);
      gl.vertexAttribDivisor(3, 0);

      gl.enableVertexAttribArray(4);
      gl.vertexAttribPointer(4, 1, gl.FLOAT, false, stride, 36);
      gl.vertexAttribDivisor(4, 0);

      const lineQuadCount = lineData.length / (4 * LINE_VERTEX_FLOATS);
      for (let index = 0; index < lineQuadCount; index += 1) {
        gl.drawArrays(gl.TRIANGLE_STRIP, index * 4, 4);
      }
    }

    // Draw rects (symbols, nets, pins).
    if (rectProgram && quadBuffer && rectInstanceBuffer) {
      gl.useProgram(rectProgram);

      const uView = gl.getUniformLocation(rectProgram, 'u_viewMatrix');
      const uRes = gl.getUniformLocation(rectProgram, 'u_resolution');
      gl.uniformMatrix3fv(uView, false, viewMatrix);
      gl.uniform2f(uRes, width, height);

      const allRects: RectLike[] = [
        ...renderList.symbols.map((el) => ({ ...el, type: el.type || 'component' })),
        ...renderList.nets.map((el) => ({ ...el, type: 'net' as const })),
        ...renderList.pins.map((el) => ({ ...el, type: 'pin' as const }))
      ];

      if (allRects.length > 0) {
        const instanceData = buildRectInstanceData(allRects, palette);

        gl.bindBuffer(gl.ARRAY_BUFFER, quadBuffer);
        gl.enableVertexAttribArray(6);
        gl.vertexAttribPointer(6, 2, gl.FLOAT, false, 0, 0);
        gl.vertexAttribDivisor(6, 0);

        gl.bindBuffer(gl.ARRAY_BUFFER, rectInstanceBuffer);
        gl.bufferData(gl.ARRAY_BUFFER, instanceData, gl.DYNAMIC_DRAW);

        const stride = RECT_FLOATS * 4;
        gl.enableVertexAttribArray(0);
        gl.vertexAttribPointer(0, 2, gl.FLOAT, false, stride, 0);
        gl.vertexAttribDivisor(0, 1);

        gl.enableVertexAttribArray(1);
        gl.vertexAttribPointer(1, 2, gl.FLOAT, false, stride, 8);
        gl.vertexAttribDivisor(1, 1);

        gl.enableVertexAttribArray(2);
        gl.vertexAttribPointer(2, 4, gl.FLOAT, false, stride, 16);
        gl.vertexAttribDivisor(2, 1);

        gl.enableVertexAttribArray(3);
        gl.vertexAttribPointer(3, 4, gl.FLOAT, false, stride, 32);
        gl.vertexAttribDivisor(3, 1);

        gl.enableVertexAttribArray(4);
        gl.vertexAttribPointer(4, 1, gl.FLOAT, false, stride, 48);
        gl.vertexAttribDivisor(4, 1);

        gl.enableVertexAttribArray(5);
        gl.vertexAttribPointer(5, 1, gl.FLOAT, false, stride, 52);
        gl.vertexAttribDivisor(5, 1);

        gl.drawArraysInstanced(gl.TRIANGLES, 0, 6, allRects.length);
      }
    }
  }

  function destroy(): void {
    destroyed = true;
    if (rectProgram) gl.deleteProgram(rectProgram);
    if (lineProgram) gl.deleteProgram(lineProgram);
    if (quadBuffer) gl.deleteBuffer(quadBuffer);
    if (rectInstanceBuffer) gl.deleteBuffer(rectInstanceBuffer);
    if (lineVertexBuffer) gl.deleteBuffer(lineVertexBuffer);
  }

  return { render, destroy };
}
