import { createExplorerModelRuntimeService } from '../services/model_runtime_service.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerModelController requires function: ${name}`);
  }
}

export function createExplorerModelController({
  dom,
  state,
  runtime,
  currentComponentSourceText,
  renderComponentTreeRows
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createExplorerModelController requires dom/state/runtime');
  }
  requireFn('currentComponentSourceText', currentComponentSourceText);
  requireFn('renderComponentTreeRows', renderComponentTreeRows);

  const runtimeService = createExplorerModelRuntimeService({
    state,
    runtime,
    currentComponentSourceText
  });

  function renderComponentTree() {
    if (!dom.componentTree) {
      return;
    }
    const hasModel = !!(state.components.model && state.components.model.nodes && state.components.model.nodes.size);
    if (!hasModel || state.components.parseError) {
      renderComponentTreeRows(dom, [], state.components.parseError || '');
      return;
    }
    const rows = runtimeService.buildComponentTreeRows(
      dom.componentTree && typeof dom.componentTree.getFilter === 'function'
        ? dom.componentTree.getFilter()
        : ''
    );
    renderComponentTreeRows(dom, rows, '');
  }

  return {
    ensureComponentSelection: runtimeService.ensureComponentSelection,
    ensureComponentGraphFocus: runtimeService.ensureComponentGraphFocus,
    currentComponentGraphFocusNode: runtimeService.currentComponentGraphFocusNode,
    setComponentGraphFocus: runtimeService.setComponentGraphFocus,
    renderComponentTree,
    currentSelectedComponentNode: runtimeService.currentSelectedComponentNode,
    rebuildComponentExplorer: runtimeService.rebuildComponentExplorer,
    refreshComponentExplorer: runtimeService.refreshComponentExplorer
  };
}
