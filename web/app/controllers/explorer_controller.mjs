import { createExplorerModelController } from './explorer_model_controller.mjs';
import { createExplorerInspectorController } from './explorer_inspector_controller.mjs';
import { createExplorerGraphController } from './explorer_graph_controller.mjs';
import {
  renderComponentTreeRows,
  renderComponentInspectorView
} from '../components/outline_panel.mjs';
import {
  renderComponentLiveSignalsView,
  renderComponentConnectionsView,
  clearComponentConnectionsView
} from '../components/schematic_panel.mjs';

function requireFn(name, fn) {
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
} = {}) {
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

  function renderComponentViews() {
    const node = modelController.currentSelectedComponentNode();
    inspectorController.renderComponentInspector(node);
    graphController.renderComponentGraphPanel();
  }

  const graphController = createExplorerGraphController({
    dom,
    state,
    runtime,
    currentComponentGraphFocusNode: modelController.currentComponentGraphFocusNode,
    currentSelectedComponentNode: modelController.currentSelectedComponentNode,
    renderComponentTree: modelController.renderComponentTree,
    renderComponentViews,
    signalLiveValueByName: inspectorController.signalLiveValueByName,
    componentSignalLookup: inspectorController.componentSignalLookup,
    resolveNodeSignalRef: inspectorController.resolveNodeSignalRef,
    collectExprSignalNames: inspectorController.collectExprSignalNames,
    findComponentSchematicEntry: inspectorController.findComponentSchematicEntry,
    summarizeExpr: inspectorController.summarizeExpr,
    renderComponentLiveSignals: inspectorController.renderComponentLiveSignals,
    renderComponentConnections: inspectorController.renderComponentConnections
  });

  function setComponentGraphFocus(nodeId, showChildren = true) {
    const changed = modelController.setComponentGraphFocus(nodeId, showChildren);
    if (!changed) {
      return;
    }
    modelController.renderComponentTree();
    renderComponentViews();
    scheduleReduxUxSync('setComponentGraphFocus');
  }

  function isComponentTabActive() {
    return state.activeTab === 'componentTab' || state.activeTab === 'componentGraphTab';
  }

  function refreshActiveComponentTab() {
    if (state.activeTab === 'componentTab') {
      inspectorController.renderComponentInspector(modelController.currentSelectedComponentNode());
    } else if (state.activeTab === 'componentGraphTab') {
      graphController.renderComponentGraphPanel();
    }
  }

  function rebuildComponentExplorer(meta = runtime.irMeta, source = currentComponentSourceText()) {
    modelController.rebuildComponentExplorer(meta, source);
    modelController.renderComponentTree();
    renderComponentViews();
  }

  function refreshComponentExplorer() {
    modelController.refreshComponentExplorer();
    modelController.renderComponentTree();
    renderComponentViews();
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
    destroyComponentGraph: graphController.destroyComponentGraph,
    signalLiveValue: inspectorController.signalLiveValue,
    rebuildComponentExplorer,
    refreshComponentExplorer
  };
}
