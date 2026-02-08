import { parseIrMeta, currentIrSourceKey } from '../lib/ir_meta_utils.mjs';
import { buildComponentModel, nodeMatchesFilter } from '../lib/model_utils.mjs';

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

  function ensureComponentSelection() {
    const model = state.components.model;
    if (!model || !model.nodes.size) {
      state.components.selectedNodeId = null;
      return;
    }
    if (state.components.selectedNodeId && model.nodes.has(state.components.selectedNodeId)) {
      return;
    }
    state.components.selectedNodeId = model.rootId;
  }

  function ensureComponentGraphFocus() {
    const model = state.components.model;
    if (!model || !model.nodes.size) {
      state.components.graphFocusId = null;
      state.components.graphShowChildren = false;
      return;
    }
    if (state.components.graphFocusId && model.nodes.has(state.components.graphFocusId)) {
      return;
    }
    state.components.graphFocusId = model.rootId;
    state.components.graphShowChildren = true;
  }

  function currentComponentGraphFocusNode() {
    const model = state.components.model;
    if (!model || !model.nodes.size) {
      return null;
    }
    ensureComponentGraphFocus();
    const id = state.components.graphFocusId || model.rootId;
    return model.nodes.get(id) || model.nodes.get(model.rootId) || null;
  }

  function setComponentGraphFocus(nodeId, showChildren = true) {
    const model = state.components.model;
    if (!model || !nodeId || !model.nodes.has(nodeId)) {
      return false;
    }
    state.components.graphFocusId = nodeId;
    state.components.graphShowChildren = !!showChildren;
    state.components.graphLastTap = null;
    state.components.graphHighlightedSignal = null;
    state.components.graphLiveValues = new Map();
    state.components.selectedNodeId = nodeId;
    return true;
  }

  function renderComponentTree() {
    if (!dom.componentTree) {
      return;
    }
    const model = state.components.model;
    if (!model || !model.nodes.size || state.components.parseError) {
      renderComponentTreeRows(dom, [], state.components.parseError || '');
      return;
    }

    const filter = String(
      dom.componentTree && typeof dom.componentTree.getFilter === 'function'
        ? dom.componentTree.getFilter()
        : ''
    ).trim().toLowerCase();
    const visibilityCache = new Map();

    function isVisible(nodeId) {
      if (!filter) {
        return true;
      }
      if (visibilityCache.has(nodeId)) {
        return visibilityCache.get(nodeId);
      }
      const node = model.nodes.get(nodeId);
      if (!node) {
        visibilityCache.set(nodeId, false);
        return false;
      }
      const visible = nodeMatchesFilter(node, filter) || node.children.some((childId) => isVisible(childId));
      visibilityCache.set(nodeId, visible);
      return visible;
    }

    const treeRows = [];
    function appendNode(nodeId, depth) {
      if (!isVisible(nodeId)) {
        return;
      }
      const node = model.nodes.get(nodeId);
      if (!node) {
        return;
      }
      treeRows.push({
        nodeId,
        depth,
        name: node.name,
        kind: node.kind,
        childCount: node.children.length,
        signalCount: node.signals.length,
        isActive: nodeId === state.components.selectedNodeId
      });

      for (const childId of node.children) {
        appendNode(childId, depth + 1);
      }
    }

    appendNode(model.rootId, 0);
    renderComponentTreeRows(dom, treeRows, '');
  }

  function currentSelectedComponentNode() {
    const model = state.components.model;
    if (!model || !state.components.selectedNodeId) {
      return null;
    }
    return model.nodes.get(state.components.selectedNodeId) || null;
  }

  function parseComponentMetaFromCurrentIr() {
    const source = currentComponentSourceText().trim();
    const sourceKey = currentIrSourceKey(source);
    if (!source) {
      state.components.model = null;
      state.components.sourceKey = sourceKey;
      state.components.parseError = 'No IR loaded.';
      state.components.selectedNodeId = null;
      state.components.graphFocusId = null;
      state.components.graphShowChildren = false;
      state.components.graphLastTap = null;
      state.components.graphHighlightedSignal = null;
      state.components.graphLiveValues = new Map();
      return;
    }
    if (state.components.sourceKey === sourceKey && state.components.model) {
      return;
    }

    try {
      const meta = parseIrMeta(source);
      state.components.model = buildComponentModel(meta);
      state.components.sourceKey = sourceKey;
      state.components.parseError = '';
      state.components.graphHighlightedSignal = null;
      state.components.graphLiveValues = new Map();
      ensureComponentSelection();
      ensureComponentGraphFocus();
    } catch (err) {
      state.components.model = null;
      state.components.sourceKey = sourceKey;
      state.components.parseError = `Component explorer parse failed: ${err.message || err}`;
      state.components.selectedNodeId = null;
      state.components.graphFocusId = null;
      state.components.graphShowChildren = false;
      state.components.graphLastTap = null;
      state.components.graphHighlightedSignal = null;
      state.components.graphLiveValues = new Map();
    }
  }

  function rebuildComponentExplorer(meta = runtime.irMeta, source = currentComponentSourceText()) {
    const sourceKey = currentIrSourceKey(source);
    if (!meta?.ir) {
      parseComponentMetaFromCurrentIr();
      return;
    }

    state.components.model = buildComponentModel(meta);
    state.components.sourceKey = sourceKey;
    state.components.parseError = '';
    state.components.graphHighlightedSignal = null;
    state.components.graphLiveValues = new Map();
    ensureComponentSelection();
    ensureComponentGraphFocus();
  }

  function refreshComponentExplorer() {
    const source = currentComponentSourceText();
    const sourceKey = currentIrSourceKey(source);
    const preferredMeta = state.components.overrideMeta || runtime.irMeta;
    if (preferredMeta?.ir) {
      if (!state.components.model || state.components.sourceKey !== sourceKey) {
        rebuildComponentExplorer(preferredMeta, source);
      }
    } else {
      parseComponentMetaFromCurrentIr();
    }
    ensureComponentSelection();
    ensureComponentGraphFocus();
  }

  return {
    ensureComponentSelection,
    ensureComponentGraphFocus,
    currentComponentGraphFocusNode,
    setComponentGraphFocus,
    renderComponentTree,
    currentSelectedComponentNode,
    rebuildComponentExplorer,
    refreshComponentExplorer
  };
}
