import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

export function bindComponentBindings({
  dom,
  state,
  components,
  scheduleReduxUxSync,
  log
}) {
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

  listeners.on(dom.componentTree, 'component-select', (event) => {
    const nodeId = event?.detail?.nodeId;
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

  listeners.on(dom.irFileInput, 'change', async (event) => {
    const file = event?.target?.files?.[0];
    if (!file) {
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
