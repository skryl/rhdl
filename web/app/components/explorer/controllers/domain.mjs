export function createComponentDomainController({
  isComponentTabActive,
  refreshActiveComponentTab,
  refreshComponentExplorer,
  renderComponentTree,
  setComponentGraphFocus,
  currentComponentGraphFocusNode,
  renderComponentViews,
  zoomComponentGraphIn,
  zoomComponentGraphOut,
  resetComponentGraphViewport,
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
    zoomGraphIn: zoomComponentGraphIn,
    zoomGraphOut: zoomComponentGraphOut,
    resetGraphView: resetComponentGraphViewport,
    clearSourceOverride: clearComponentSourceOverride,
    resetExplorerState: resetComponentExplorerState
  };
}
