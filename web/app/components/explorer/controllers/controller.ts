import { createExplorerModelController } from './model_controller';
import { createExplorerInspectorController } from './inspector_controller';
import { createExplorerGraphController } from './graph/controller';
import { resolveComponentRefreshPlan } from './refresh_plan';
import {
  renderComponentTreeRows,
  renderComponentInspectorView
} from '../ui/outline_panel';
import {
  renderComponentLiveSignalsView,
  renderComponentConnectionsView,
  clearComponentConnectionsView
} from '../ui/schematic_panel';

function requireFn(name: any, fn: any) {
  if (typeof fn !== 'function') {
    throw new Error(`createComponentExplorerController requires function: ${name}`);
  }
}

export function createComponentExplorerController({
  dom,
  state,
  runtime,
  scheduleReduxUxSync,
  currentComponentSourceText,
  componentSignalPreviewLimit = 180
}: any = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createComponentExplorerController requires dom/state/runtime');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('currentComponentSourceText', currentComponentSourceText);

  const modelController = createExplorerModelController({
    dom,
    state,
    runtime,
    currentComponentSourceText,
    renderComponentTreeRows
  });

  const inspectorController = createExplorerInspectorController({
    dom,
    state,
    runtime,
    componentSignalPreviewLimit,
    renderComponentInspectorView,
    renderComponentLiveSignalsView,
    renderComponentConnectionsView,
    clearComponentConnectionsView
  });

  function renderComponentInspectorOnly() {
    const node = modelController.currentSelectedComponentNode();
    inspectorController.renderComponentInspector(node);
  }

  function renderComponentGraphOnly() {
    graphController.renderComponentGraphPanel();
  }

  function renderComponentViews() {
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
      return;
    }
    if (plan.renderGraph) {
      renderComponentGraphOnly();
      return;
    }
  }

  const graphController = createExplorerGraphController({
    dom,
    state,
    runtime,
    currentComponentGraphFocusNode: modelController.currentComponentGraphFocusNode,
    currentSelectedComponentNode: modelController.currentSelectedComponentNode,
    renderComponentTree: modelController.renderComponentTree,
    renderComponentViews,
    createSchematicElements: inspectorController.createSchematicElements,
    signalLiveValueByName: inspectorController.signalLiveValueByName,
    renderComponentLiveSignals: inspectorController.renderComponentLiveSignals,
    renderComponentConnections: inspectorController.renderComponentConnections
  });

  function setComponentGraphFocus(nodeId: any, showChildren = true) {
    const changed = modelController.setComponentGraphFocus(nodeId, showChildren);
    if (!changed) {
      return;
    }
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderTree) {
      modelController.renderComponentTree();
    }
    renderComponentViews();
    scheduleReduxUxSync('setComponentGraphFocus');
  }

  function isComponentTabActive() {
    return state.activeTab === 'componentTab' || state.activeTab === 'componentGraphTab';
  }

  function refreshActiveComponentTab() {
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
    } else if (plan.renderGraph) {
      renderComponentGraphOnly();
    }
  }

  function rebuildComponentExplorer(meta = runtime.irMeta, source = currentComponentSourceText()) {
    modelController.rebuildComponentExplorer(meta, source);
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderTree) {
      modelController.renderComponentTree();
    }
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
    }
    if (plan.renderGraph) {
      renderComponentGraphOnly();
    }
  }

  function refreshComponentExplorer() {
    modelController.refreshComponentExplorer();
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderTree) {
      modelController.renderComponentTree();
    }
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
    }
    if (plan.renderGraph) {
      renderComponentGraphOnly();
    }
  }

  function zoomComponentGraphIn() {
    return graphController.zoomInComponentGraph();
  }

  function zoomComponentGraphOut() {
    return graphController.zoomOutComponentGraph();
  }

  function resetComponentGraphViewport() {
    return graphController.resetComponentGraphViewport();
  }

  return {
    ensureComponentSelection: modelController.ensureComponentSelection,
    ensureComponentGraphFocus: modelController.ensureComponentGraphFocus,
    currentComponentGraphFocusNode: modelController.currentComponentGraphFocusNode,
    setComponentGraphFocus,
    renderComponentTree: modelController.renderComponentTree,
    currentSelectedComponentNode: modelController.currentSelectedComponentNode,
    isComponentTabActive,
    renderComponentViews,
    refreshActiveComponentTab,
    zoomComponentGraphIn,
    zoomComponentGraphOut,
    resetComponentGraphViewport,
    destroyComponentGraph: graphController.destroyComponentGraph,
    signalLiveValue: inspectorController.signalLiveValue,
    rebuildComponentExplorer,
    refreshComponentExplorer
  };
}
