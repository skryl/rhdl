function readSignalHighlight(target) {
  const signalName = String(target?.data('signalName') || '').trim();
  const liveName = String(target?.data('liveName') || '').trim();
  if (!signalName && !liveName) {
    return null;
  }
  return {
    signalName: signalName || null,
    liveName: liveName || null
  };
}

export function bindGraphInteractions({
  cy,
  state,
  model,
  renderComponentTree,
  renderComponentViews,
  now = () => Date.now(),
  doubleTapMs = 320
} = {}) {
  if (!cy || !state || !model) {
    throw new Error('bindGraphInteractions requires cy, state, and model');
  }
  if (typeof renderComponentTree !== 'function' || typeof renderComponentViews !== 'function') {
    throw new Error('bindGraphInteractions requires render callbacks');
  }

  cy.on('tap', 'node', (evt) => {
    const target = evt?.target;
    if (!target) {
      return;
    }
    const componentId = String(target.data('componentId') || '').trim();
    const nodeRole = String(target.data('nodeRole') || '');

    if (!componentId || !model.nodes.has(componentId)) {
      if (nodeRole === 'net' || nodeRole === 'pin') {
        state.components.graphHighlightedSignal = readSignalHighlight(target);
        renderComponentViews();
      }
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
  });

  cy.on('tap', 'edge', (evt) => {
    const target = evt?.target;
    if (!target) {
      return;
    }
    state.components.graphHighlightedSignal = readSignalHighlight(target);
    renderComponentViews();
  });

  cy.on('tap', (evt) => {
    if (evt?.target === cy) {
      state.components.graphHighlightedSignal = null;
      renderComponentViews();
    }
  });
}

