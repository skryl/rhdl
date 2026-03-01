import { createListenerGroup } from '../../../core/bindings/listener_group';

interface BindingsDom {
  componentTree?: EventTarget | null;
  componentGraphTopBtn?: EventTarget | null;
  componentGraphUpBtn?: EventTarget | null;
  componentGraphZoomInBtn?: EventTarget | null;
  componentGraphZoomOutBtn?: EventTarget | null;
  componentGraphResetViewBtn?: EventTarget | null;
  irFileInput?: EventTarget | null;
  irJson?: (EventTarget & { value?: unknown }) | null;
}

interface BindingsState {
  components: {
    model?: { rootId?: string | null } | null;
    selectedNodeId: string | null;
  };
}

interface ComponentBindingsController {
  renderTree: () => void;
  setGraphFocus: (nodeId: string, showChildren?: boolean) => void;
  currentGraphFocusNode: () => { parentId: string | null } | null;
  renderViews: () => void;
  zoomGraphIn?: () => void;
  zoomGraphOut?: () => void;
  resetGraphView?: () => void;
  clearSourceOverride: () => void;
  resetExplorerState: () => void;
  isTabActive: () => boolean;
  refreshExplorer: () => void;
}

interface BindComponentBindingsOptions {
  dom: BindingsDom;
  state: BindingsState;
  components: ComponentBindingsController;
  scheduleReduxUxSync: (reason: string) => void;
  log: (message: string) => void;
}

function readNodeId(event: unknown): string | null {
  const detail = event && typeof event === 'object' && 'detail' in event
    ? (event as { detail?: { nodeId?: unknown } }).detail
    : null;
  const nodeId = String(detail?.nodeId || '').trim();
  return nodeId || null;
}

function readFileFromEvent(event: unknown): File | null {
  const target = event && typeof event === 'object' && 'target' in event
    ? (event as { target?: { files?: FileList | null } }).target
    : null;
  return target?.files?.[0] || null;
}

export function bindComponentBindings({
  dom,
  state,
  components,
  scheduleReduxUxSync,
  log
}: BindComponentBindingsOptions) {
  const listeners = createListenerGroup();

  listeners.on(dom.componentTree, 'component-filter-change', () => {
    components.renderTree();
    scheduleReduxUxSync('componentFilterChange');
  });

  listeners.on(dom.componentGraphTopBtn, 'click', () => {
    const model = state.components.model;
    if (!model?.rootId) {
      return;
    }
    components.setGraphFocus(model.rootId, true);
  });

  listeners.on(dom.componentGraphUpBtn, 'click', () => {
    const focusNode = components.currentGraphFocusNode();
    if (!focusNode?.parentId) {
      return;
    }
    components.setGraphFocus(focusNode.parentId, true);
  });

  listeners.on(dom.componentGraphZoomInBtn, 'click', () => {
    if (typeof components.zoomGraphIn === 'function') {
      components.zoomGraphIn();
    }
  });

  listeners.on(dom.componentGraphZoomOutBtn, 'click', () => {
    if (typeof components.zoomGraphOut === 'function') {
      components.zoomGraphOut();
    }
  });

  listeners.on(dom.componentGraphResetViewBtn, 'click', () => {
    if (typeof components.resetGraphView === 'function') {
      components.resetGraphView();
    }
  });

  listeners.on(dom.componentTree, 'component-select', (event: unknown) => {
    const nodeId = readNodeId(event);
    if (!nodeId) {
      return;
    }
    if (state.components.selectedNodeId !== nodeId) {
      state.components.selectedNodeId = nodeId;
      components.renderTree();
      components.renderViews();
      scheduleReduxUxSync('componentSelect');
    }
  });

  listeners.on(dom.irFileInput, 'change', async (event: unknown) => {
    const file = readFileFromEvent(event);
    if (!file || !dom.irJson) {
      return;
    }

    dom.irJson.value = await file.text();
    components.clearSourceOverride();
    components.resetExplorerState();
    log(`Loaded IR file: ${file.name}`);
    if (components.isTabActive()) {
      components.refreshExplorer();
    }
  });

  listeners.on(dom.irJson, 'input', () => {
    components.clearSourceOverride();
    components.resetExplorerState();
    if (components.isTabActive()) {
      components.refreshExplorer();
    }
  });

  return () => {
    listeners.dispose();
  };
}
