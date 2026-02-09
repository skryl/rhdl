import { parseIrMeta, currentIrSourceKey } from '../../../core/lib/ir_meta_utils.mjs';
import { buildComponentModel, nodeMatchesFilter } from '../lib/model_utils.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerModelRuntimeService requires function: ${name}`);
  }
}

function clearGraphState(components) {
  components.graphFocusId = null;
  components.graphShowChildren = false;
  components.graphLastTap = null;
  components.graphHighlightedSignal = null;
  components.graphLiveValues = new Map();
}

function clearModelState(components, sourceKey, parseError) {
  components.model = null;
  components.sourceKey = sourceKey;
  components.parseError = parseError;
  components.selectedNodeId = null;
  clearGraphState(components);
}

function resetGraphActivity(components) {
  components.graphLastTap = null;
  components.graphHighlightedSignal = null;
  components.graphLiveValues = new Map();
}

export function createExplorerModelRuntimeService({
  state,
  runtime,
  currentComponentSourceText
} = {}) {
  if (!state || !runtime) {
    throw new Error('createExplorerModelRuntimeService requires state/runtime');
  }
  requireFn('currentComponentSourceText', currentComponentSourceText);

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
    resetGraphActivity(state.components);
    state.components.selectedNodeId = nodeId;
    return true;
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
      clearModelState(state.components, sourceKey, 'No IR loaded.');
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
      resetGraphActivity(state.components);
      ensureComponentSelection();
      ensureComponentGraphFocus();
    } catch (err) {
      clearModelState(
        state.components,
        sourceKey,
        `Component explorer parse failed: ${err.message || err}`
      );
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
    resetGraphActivity(state.components);
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

  function buildComponentTreeRows(filterText = '') {
    const model = state.components.model;
    if (!model || !model.nodes.size || state.components.parseError) {
      return [];
    }

    const filter = String(filterText).trim().toLowerCase();
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
    return treeRows;
  }

  return {
    ensureComponentSelection,
    ensureComponentGraphFocus,
    currentComponentGraphFocusNode,
    setComponentGraphFocus,
    currentSelectedComponentNode,
    rebuildComponentExplorer,
    refreshComponentExplorer,
    buildComponentTreeRows
  };
}
