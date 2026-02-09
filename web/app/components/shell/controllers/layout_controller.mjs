function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createDashboardLayoutController requires function: ${name}`);
  }
}

export function createDashboardLayoutController({
  state,
  documentRef,
  windowRef,
  storage,
  layoutStorageKey,
  minRowHeight,
  rootConfigs,
  parseDashboardLayouts,
  serializeDashboardLayouts,
  withDashboardRowHeight,
  normalizeDashboardSpan,
  safeSlugToken,
  dashboardRowSignature,
  dashboardDropPosition,
  bindDashboardResizeEvents,
  bindDashboardPanelEvents,
  isComponentTabActive,
  refreshActiveComponentTab,
  refreshMemoryView,
  getActiveTab,
  createDashboardLayoutManager
} = {}) {
  if (!state) {
    throw new Error('createDashboardLayoutController requires state');
  }
  requireFn('getActiveTab', getActiveTab);
  requireFn('createDashboardLayoutManager', createDashboardLayoutManager);

  let dashboardLayoutManager = null;

  function getDashboardLayoutManager() {
    if (!dashboardLayoutManager) {
      dashboardLayoutManager = createDashboardLayoutManager({
        state,
        documentRef,
        windowRef,
        storage,
        layoutStorageKey,
        minRowHeight,
        rootConfigs,
        parseDashboardLayouts,
        serializeDashboardLayouts,
        withDashboardRowHeight,
        normalizeDashboardSpan,
        safeSlugToken,
        dashboardRowSignature,
        dashboardDropPosition,
        bindDashboardResizeEvents,
        bindDashboardPanelEvents,
        isComponentTabActive,
        refreshActiveComponentTab,
        refreshMemoryView,
        getActiveTab
      });
    }
    return dashboardLayoutManager;
  }

  function disposeDashboardLayoutBuilder() {
    if (!dashboardLayoutManager) {
      return;
    }
    dashboardLayoutManager.dispose();
  }

  function refreshDashboardRowSizing(rootKey) {
    getDashboardLayoutManager().refreshRowSizing(rootKey);
  }

  function refreshAllDashboardRowSizing() {
    getDashboardLayoutManager().refreshAllRowSizing();
  }

  function initializeDashboardLayoutBuilder() {
    getDashboardLayoutManager().initialize();
  }

  return {
    getDashboardLayoutManager,
    disposeDashboardLayoutBuilder,
    refreshDashboardRowSizing,
    refreshAllDashboardRowSizing,
    initializeDashboardLayoutBuilder
  };
}
