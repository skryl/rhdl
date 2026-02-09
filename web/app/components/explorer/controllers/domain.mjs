export function createComponentDomainController({
  isComponentTabActive,
  refreshActiveComponentTab,
  refreshComponentExplorer,
  renderComponentTree,
  setComponentGraphFocus,
  currentComponentGraphFocusNode,
  renderComponentViews,
  clearComponentSourceOverride,
  resetComponentExplorerState
} = {}) {
  return {
    isTabActive: isComponentTabActive,
    refreshActiveTab: refreshActiveComponentTab,
    refreshExplorer: refreshComponentExplorer,
    renderTree: renderComponentTree,
    setGraphFocus: setComponentGraphFocus,
    currentGraphFocusNode: currentComponentGraphFocusNode,
    renderViews: renderComponentViews,
    clearSourceOverride: clearComponentSourceOverride,
    resetExplorerState: resetComponentExplorerState
  };
}
