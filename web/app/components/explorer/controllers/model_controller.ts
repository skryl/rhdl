import { createExplorerModelRuntimeService } from '../services/model_runtime_service';
import type { ExplorerDomRefs, ExplorerRuntimeLike, ExplorerStateLike, TreeRow } from '../lib/types';

interface ModelControllerOptions {
  dom: ExplorerDomRefs;
  state: ExplorerStateLike;
  runtime: ExplorerRuntimeLike;
  currentComponentSourceText: () => string;
  renderComponentTreeRows: (
    dom: ExplorerDomRefs,
    treeRows: TreeRow[],
    parseError: string
  ) => void;
}

function requireFn(name: string, fn: unknown): void {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerModelController requires function: ${name}`);
  }
}

function hasModel(state: ExplorerStateLike): boolean {
  const model = state.components.model;
  return !!(model && model.nodes && model.nodes.size > 0);
}

export function createExplorerModelController({
  dom,
  state,
  runtime,
  currentComponentSourceText,
  renderComponentTreeRows
}: ModelControllerOptions) {
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

  function renderComponentTree(): void {
    if (!dom.componentTree) {
      return;
    }
    if (!hasModel(state) || state.components.parseError) {
      renderComponentTreeRows(dom, [], state.components.parseError || '');
      return;
    }

    const filter = dom.componentTree && typeof dom.componentTree.getFilter === 'function'
      ? String(dom.componentTree.getFilter())
      : '';
    const rows = runtimeService.buildComponentTreeRows(filter);
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
