// D3-style interaction layer for the RTL schematic renderer.
// Handles click dispatch via spatial index, double-tap detection for drill-down.

const DOUBLE_TAP_MS = 320;

function isComponent(element) {
  return element.type === 'component' || element.type === 'focus';
}

function isNetOrPin(element) {
  return !!(element.signalName || element.liveName) && !isComponent(element);
}

function readSignalHighlight(element) {
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
} = {}) {
  if (!canvas || !state || !model) {
    throw new Error('bindD3Interactions requires canvas, state, and model');
  }
  if (typeof renderComponentTree !== 'function' || typeof renderComponentViews !== 'function') {
    throw new Error('bindD3Interactions requires render callbacks');
  }

  function toWorldCoords(clientX, clientY) {
    const rect = canvas.getBoundingClientRect();
    const sx = clientX - rect.left;
    const sy = clientY - rect.top;

    if (viewport) {
      return {
        x: (sx - (viewport.x || 0)) / (viewport.scale || 1),
        y: (sy - (viewport.y || 0)) / (viewport.scale || 1)
      };
    }
    return { x: sx, y: sy };
  }

  function handleClick(evt) {
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

  canvas.addEventListener('click', handleClick);

  function destroy() {
    canvas.removeEventListener('click', handleClick);
  }

  return { destroy };
}
