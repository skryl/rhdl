import { parseIrMeta, currentIrSourceKey } from '../../../core/lib/ir_meta_utils';
import { buildComponentModel, nodeMatchesFilter } from '../lib/model_utils';
import type {
  ComponentModel,
  ComponentNode,
  IrMetaLike,
  ExplorerRuntimeLike,
  TreeRow
} from '../lib/types';

interface ModelRuntimeState {
  components: {
    model: ComponentModel | null;
    selectedNodeId: string | null;
    graphFocusId: string | null;
    graphShowChildren: boolean;
    graphLastTap: { nodeId: string; timeMs: number } | null;
    graphHighlightedSignal: { signalName: string | null; liveName: string | null } | null;
    graphLiveValues: Map<string, string>;
    sourceKey: string;
    parseError: string;
    overrideMeta?: IrMetaLike | null;
  };
}

interface ModelRuntimeServiceOptions {
  state: ModelRuntimeState;
  runtime: ExplorerRuntimeLike;
  currentComponentSourceText: () => string;
}

function requireFn(name: string, fn: unknown): void {
  if (typeof fn !== 'function') {
    throw new Error(`createExplorerModelRuntimeService requires function: ${name}`);
  }
}

function clearGraphState(components: ModelRuntimeState['components']): void {
  components.graphFocusId = null;
  components.graphShowChildren = false;
  components.graphLastTap = null;
  components.graphHighlightedSignal = null;
  components.graphLiveValues = new Map<string, string>();
}

function clearModelState(
  components: ModelRuntimeState['components'],
  sourceKey: string,
  parseError: string
): void {
  components.model = null;
  components.sourceKey = sourceKey;
  components.parseError = parseError;
  components.selectedNodeId = null;
  clearGraphState(components);
}

function resetGraphActivity(components: ModelRuntimeState['components']): void {
  components.graphLastTap = null;
  components.graphHighlightedSignal = null;
  components.graphLiveValues = new Map<string, string>();
}

function normalizeNodeId(nodeId: unknown): string | null {
  const id = String(nodeId || '').trim();
  return id || null;
}

function modelHasNodes(model: ComponentModel | null): model is ComponentModel {
  return !!model && model.nodes.size > 0;
}

export function createExplorerModelRuntimeService({
  state,
  runtime,
  currentComponentSourceText
}: ModelRuntimeServiceOptions) {
  if (!state || !runtime) {
    throw new Error('createExplorerModelRuntimeService requires state/runtime');
  }
  requireFn('currentComponentSourceText', currentComponentSourceText);

  function ensureComponentSelection(): void {
    const model = state.components.model;
    if (!modelHasNodes(model)) {
      state.components.selectedNodeId = null;
      return;
    }
    if (state.components.selectedNodeId && model.nodes.has(state.components.selectedNodeId)) {
      return;
    }
    state.components.selectedNodeId = model.rootId;
  }

  function ensureComponentGraphFocus(): void {
    const model = state.components.model;
    if (!modelHasNodes(model)) {
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

  function currentComponentGraphFocusNode(): ComponentNode | null {
    const model = state.components.model;
    if (!modelHasNodes(model)) {
      return null;
    }
    ensureComponentGraphFocus();
    const id = state.components.graphFocusId || model.rootId;
    return (id ? model.nodes.get(id) : null) || (model.rootId ? model.nodes.get(model.rootId) || null : null);
  }

  function setComponentGraphFocus(nodeId: unknown, showChildren = true): boolean {
    const model = state.components.model;
    const normalizedId = normalizeNodeId(nodeId);
    if (!modelHasNodes(model) || !normalizedId || !model.nodes.has(normalizedId)) {
      return false;
    }
    state.components.graphFocusId = normalizedId;
    state.components.graphShowChildren = !!showChildren;
    resetGraphActivity(state.components);
    state.components.selectedNodeId = normalizedId;
    return true;
  }

  function currentSelectedComponentNode(): ComponentNode | null {
    const model = state.components.model;
    if (!model || !state.components.selectedNodeId) {
      return null;
    }
    return model.nodes.get(state.components.selectedNodeId) || null;
  }

  function parseComponentMetaFromCurrentIr(): void {
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
      const message = err instanceof Error ? err.message : String(err);
      clearModelState(
        state.components,
        sourceKey,
        `Component explorer parse failed: ${message}`
      );
    }
  }

  function rebuildComponentExplorer(
    meta = runtime.irMeta,
    source = currentComponentSourceText()
  ): void {
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

  function refreshComponentExplorer(): void {
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

  function buildComponentTreeRows(filterText = ''): TreeRow[] {
    const model = state.components.model;
    if (!modelHasNodes(model) || state.components.parseError) {
      return [];
    }
    const modelRef = model;

    const filter = String(filterText).trim().toLowerCase();
    const visibilityCache = new Map<string, boolean>();

    function isVisible(nodeId: string): boolean {
      if (!filter) {
        return true;
      }
      if (visibilityCache.has(nodeId)) {
        return visibilityCache.get(nodeId) || false;
      }
      const node = modelRef.nodes.get(nodeId);
      if (!node) {
        visibilityCache.set(nodeId, false);
        return false;
      }
      const visible = nodeMatchesFilter(node, filter)
        || node.children.some((childId) => isVisible(childId));
      visibilityCache.set(nodeId, visible);
      return visible;
    }

    const treeRows: TreeRow[] = [];

    function appendNode(nodeId: string, depth: number): void {
      if (!isVisible(nodeId)) {
        return;
      }
      const node = modelRef.nodes.get(nodeId);
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

    if (modelRef.rootId) {
      appendNode(modelRef.rootId, 0);
    }
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
