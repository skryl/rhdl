import { createListenerGroup } from './listener_bindings.mjs';

export function bindComponentBindings({ dom, state, actions }) {
  const listeners = createListenerGroup();

  listeners.on(dom.componentTree, 'component-filter-change', () => {
    actions.renderComponentTree();
    actions.scheduleReduxUxSync('componentFilterChange');
  });

  listeners.on(dom.componentGraphTopBtn, 'click', () => {
    const model = state.components.model;
    if (!model?.rootId) {
      return;
    }
    actions.setComponentGraphFocus(model.rootId, true);
  });

  listeners.on(dom.componentGraphUpBtn, 'click', () => {
    const focusNode = actions.currentComponentGraphFocusNode();
    if (!focusNode?.parentId) {
      return;
    }
    actions.setComponentGraphFocus(focusNode.parentId, true);
  });

  listeners.on(dom.componentTree, 'component-select', (event) => {
    const nodeId = event?.detail?.nodeId;
    if (!nodeId) {
      return;
    }
    if (state.components.selectedNodeId !== nodeId) {
      state.components.selectedNodeId = nodeId;
      actions.renderComponentTree();
      actions.renderComponentViews();
      actions.scheduleReduxUxSync('componentSelect');
    }
  });

  listeners.on(dom.irFileInput, 'change', async (event) => {
    const file = event?.target?.files?.[0];
    if (!file) {
      return;
    }

    dom.irJson.value = await file.text();
    actions.clearComponentSourceOverride();
    actions.resetComponentExplorerState();
    actions.log(`Loaded IR file: ${file.name}`);
    if (actions.isComponentTabActive()) {
      actions.refreshComponentExplorer();
    }
  });

  listeners.on(dom.irJson, 'input', () => {
    actions.clearComponentSourceOverride();
    actions.resetComponentExplorerState();
    if (actions.isComponentTabActive()) {
      actions.refreshComponentExplorer();
    }
  });

  return () => {
    listeners.dispose();
  };
}
