import { createExplorerGraphRuntimeService } from '../../services/graph_runtime_service.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerGraphController requires function: ${name}`);
  }
}

export function createExplorerGraphController({
  dom,
  state,
  runtime,
  currentComponentGraphFocusNode,
  currentSelectedComponentNode,
  renderComponentTree,
  renderComponentViews,
  createSchematicElements,
  signalLiveValueByName,
  renderComponentLiveSignals,
  renderComponentConnections
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createExplorerGraphController requires dom/state/runtime');
  }
  requireFn('currentComponentGraphFocusNode', currentComponentGraphFocusNode);
  requireFn('currentSelectedComponentNode', currentSelectedComponentNode);
  requireFn('renderComponentTree', renderComponentTree);
  requireFn('renderComponentViews', renderComponentViews);
  requireFn('createSchematicElements', createSchematicElements);
  requireFn('signalLiveValueByName', signalLiveValueByName);
  requireFn('renderComponentLiveSignals', renderComponentLiveSignals);
  requireFn('renderComponentConnections', renderComponentConnections);

  const runtimeService = createExplorerGraphRuntimeService({
    dom,
    state,
    currentComponentGraphFocusNode,
    renderComponentTree,
    renderComponentViews,
    createSchematicElements,
    signalLiveValueByName
  });

  function renderComponentGraphPanel() {
    const selectedNode = currentSelectedComponentNode();
    const focusNode = currentComponentGraphFocusNode();
    const panelState = runtimeService.describeComponentGraphPanel({ selectedNode, focusNode });
    if (dom.componentGraphTitle) {
      dom.componentGraphTitle.textContent = panelState.title;
    }
    if (dom.componentGraphMeta) {
      dom.componentGraphMeta.textContent = panelState.meta;
    }
    if (dom.componentGraphFocusPath) {
      dom.componentGraphFocusPath.textContent = panelState.focusPath;
    }
    if (dom.componentGraphTopBtn) {
      dom.componentGraphTopBtn.disabled = panelState.topDisabled;
    }
    if (dom.componentGraphUpBtn) {
      dom.componentGraphUpBtn.disabled = panelState.upDisabled;
    }

    if (!selectedNode || !focusNode) {
      runtimeService.renderComponentVisual({
        node: null,
        model: null,
        rerender: renderComponentGraphPanel
      });
      renderComponentLiveSignals(null);
      renderComponentConnections(null);
      return;
    }

    runtimeService.renderComponentVisual({
      node: selectedNode,
      model: state.components.model,
      rerender: renderComponentGraphPanel
    });
    renderComponentLiveSignals(focusNode);
    renderComponentConnections(focusNode);
  }

  return {
    destroyComponentGraph: runtimeService.destroyComponentGraph,
    renderComponentGraphPanel
  };
}
