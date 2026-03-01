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
import type {
  ComponentModel,
  ComponentNode,
  ExplorerDomRefs,
  ExplorerRuntimeLike,
  ExplorerStateLike
} from '../lib/types';

interface ComponentExplorerControllerOptions {
  dom: ExplorerDomRefs;
  state: ExplorerStateLike;
  runtime: ExplorerRuntimeLike;
  scheduleReduxUxSync: (reason: string) => void;
  currentComponentSourceText: () => string;
  componentSignalPreviewLimit?: number;
}

function requireFn(name: string, fn: unknown): void {
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
}: ComponentExplorerControllerOptions) {
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

  function renderComponentInspectorOnly(): void {
    const node = modelController.currentSelectedComponentNode();
    inspectorController.renderComponentInspector(node);
  }

  function renderComponentViews(): void {
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
      return;
    }
    if (plan.renderGraph) {
      graphController.renderComponentGraphPanel();
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

  function setComponentGraphFocus(nodeId: unknown, showChildren = true): void {
    const normalizedId = String(nodeId || '').trim();
    if (!normalizedId) {
      return;
    }

    const changed = modelController.setComponentGraphFocus(normalizedId, showChildren);
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

  function isComponentTabActive(): boolean {
    return state.activeTab === 'componentTab' || state.activeTab === 'componentGraphTab';
  }

  function refreshActiveComponentTab(): void {
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
    } else if (plan.renderGraph) {
      graphController.renderComponentGraphPanel();
    }
  }

  function rebuildComponentExplorer(
    meta = runtime.irMeta,
    source = currentComponentSourceText()
  ): void {
    modelController.rebuildComponentExplorer(meta, source);
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderTree) {
      modelController.renderComponentTree();
    }
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
    }
    if (plan.renderGraph) {
      graphController.renderComponentGraphPanel();
    }
  }

  function refreshComponentExplorer(): void {
    modelController.refreshComponentExplorer();
    const plan = resolveComponentRefreshPlan(state.activeTab);
    if (plan.renderTree) {
      modelController.renderComponentTree();
    }
    if (plan.renderInspector) {
      renderComponentInspectorOnly();
    }
    if (plan.renderGraph) {
      graphController.renderComponentGraphPanel();
    }
  }

  function zoomComponentGraphIn(): boolean {
    return graphController.zoomInComponentGraph();
  }

  function zoomComponentGraphOut(): boolean {
    return graphController.zoomOutComponentGraph();
  }

  function resetComponentGraphViewport(): boolean {
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
