// D3-style interaction layer for the RTL schematic renderer.
// Handles click dispatch via spatial index, double-tap detection for drill-down.

const DOUBLE_TAP_MS = 320;
const ZOOM_SENSITIVITY = 0.0015;
const MIN_ZOOM_SCALE = 0.05;
const MAX_ZOOM_SCALE = 8;
const PAN_DRAG_THRESHOLD = 3;

function clamp(value: any, min: any, max: any) {
  return Math.min(max, Math.max(min, value));
}

function isComponent(element: any) {
  return element.type === 'component' || element.type === 'focus';
}

function isNetOrPin(element: any) {
  return !!(element.signalName || element.liveName) && !isComponent(element);
}

function readSignalHighlight(element: any) {
  const signalName = String(element.signalName || '').trim();
  const liveName = String(element.liveName || '').trim();
  if (!signalName && !liveName) return null;
  return { signalName: signalName || null, liveName: liveName || null };
}

export function bindD3Interactions({
  canvas,
  state,
  model,
  spatialIndex,
  renderComponentTree,
  renderComponentViews,
  requestRender,
  now = () => Date.now(),
  doubleTapMs = DOUBLE_TAP_MS,
  viewport = null
}: any = {}) {
  if (!canvas || !state || !model) {
    throw new Error('bindD3Interactions requires canvas, state, and model');
  }
  if (typeof renderComponentTree !== 'function' || typeof renderComponentViews !== 'function') {
    throw new Error('bindD3Interactions requires render callbacks');
  }

  const renderNow = typeof requestRender === 'function' ? requestRender : () => {};
  const globalTarget =
    typeof window !== 'undefined' && typeof window.addEventListener === 'function'
      ? window
      : canvas;

  let panState: any = null;
  let suppressClick = false;
  const wheelListenerOptions = { passive: false };

  function toScreenCoords(clientX: any, clientY: any) {
    const rect = canvas.getBoundingClientRect();
    return {
      x: clientX - rect.left,
      y: clientY - rect.top
    };
  }

  function toWorldCoords(clientX: any, clientY: any) {
    const screen = toScreenCoords(clientX, clientY);
    const sx = screen.x;
    const sy = screen.y;

    if (viewport) {
      return {
        x: (sx - (viewport.x || 0)) / (viewport.scale || 1),
        y: (sy - (viewport.y || 0)) / (viewport.scale || 1)
      };
    }
    return { x: sx, y: sy };
  }

  function handleClick(evt: any) {
    if (suppressClick) {
      suppressClick = false;
      return;
    }

    const { x, y } = toWorldCoords(evt.clientX, evt.clientY);
    const hit = spatialIndex.queryPoint(x, y);

    if (!hit) {
      // canvas tap — clear highlight
      state.components.graphHighlightedSignal = null;
      renderComponentViews();
      return;
    }

    // net or pin tap — highlight signal
    if (isNetOrPin(hit)) {
      state.components.graphHighlightedSignal = readSignalHighlight(hit);
      renderComponentViews();
      return;
    }

    // component tap
    if (isComponent(hit)) {
      const componentId = hit.componentId;
      if (!componentId || !model.nodes.has(componentId)) {
        return;
      }

      const nowMs = now();
      const lastTap = state.components.graphLastTap;
      const isDoubleTap = !!(lastTap && lastTap.nodeId === componentId && (nowMs - lastTap.timeMs) < doubleTapMs);
      state.components.graphLastTap = { nodeId: componentId, timeMs: nowMs };

      if (state.components.selectedNodeId !== componentId) {
        state.components.selectedNodeId = componentId;
        renderComponentTree();
      }

      if (isDoubleTap) {
        state.components.graphFocusId = componentId;
        state.components.graphShowChildren = true;
        state.components.graphHighlightedSignal = null;
      }

      renderComponentViews();
    }
  }

  function handleWheel(evt: any) {
    if (!viewport) return;
    const prevScale = Number.isFinite(viewport.scale) ? viewport.scale : 1;
    const zoom = Math.exp(-Number(evt.deltaY || 0) * ZOOM_SENSITIVITY);
    const nextScale = clamp(prevScale * zoom, MIN_ZOOM_SCALE, MAX_ZOOM_SCALE);
    if (!Number.isFinite(nextScale) || Math.abs(nextScale - prevScale) < 1e-6) {
      return;
    }

    const { x: sx, y: sy } = toScreenCoords(evt.clientX, evt.clientY);
    const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
    const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
    const worldX = (sx - tx) / prevScale;
    const worldY = (sy - ty) / prevScale;

    viewport.scale = nextScale;
    viewport.x = sx - (worldX * nextScale);
    viewport.y = sy - (worldY * nextScale);

    if (typeof evt.preventDefault === 'function') {
      evt.preventDefault();
    }
    renderNow();
  }

  function handleMouseDown(evt: any) {
    if (!viewport) return;
    if (evt.button !== 0) return;
    const tx = Number.isFinite(viewport.x) ? viewport.x : 0;
    const ty = Number.isFinite(viewport.y) ? viewport.y : 0;
    panState = {
      startX: Number(evt.clientX) || 0,
      startY: Number(evt.clientY) || 0,
      baseX: tx,
      baseY: ty,
      dragged: false
    };
  }

  function handleMouseMove(evt: any) {
    if (!panState || !viewport) return;
    const dx = (Number(evt.clientX) || 0) - panState.startX;
    const dy = (Number(evt.clientY) || 0) - panState.startY;
    if (!panState.dragged) {
      const moved = Math.abs(dx) >= PAN_DRAG_THRESHOLD || Math.abs(dy) >= PAN_DRAG_THRESHOLD;
      if (!moved) return;
      panState.dragged = true;
    }

    viewport.x = panState.baseX + dx;
    viewport.y = panState.baseY + dy;
    if (typeof evt.preventDefault === 'function') {
      evt.preventDefault();
    }
    renderNow();
  }

  function handleMouseUp(evt: any) {
    if (!panState) return;
    if (panState.dragged) {
      suppressClick = true;
      if (typeof evt.preventDefault === 'function') {
        evt.preventDefault();
      }
    }
    panState = null;
  }

  canvas.addEventListener('click', handleClick);
  canvas.addEventListener('wheel', handleWheel, wheelListenerOptions);
  canvas.addEventListener('mousedown', handleMouseDown);
  globalTarget.addEventListener('mousemove', handleMouseMove);
  globalTarget.addEventListener('mouseup', handleMouseUp);

  function destroy() {
    canvas.removeEventListener('click', handleClick);
    canvas.removeEventListener('wheel', handleWheel, wheelListenerOptions);
    canvas.removeEventListener('mousedown', handleMouseDown);
    globalTarget.removeEventListener('mousemove', handleMouseMove);
    globalTarget.removeEventListener('mouseup', handleMouseUp);
  }

  return { destroy };
}
