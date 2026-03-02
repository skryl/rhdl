interface ComponentDomainControllerOptions {
  isComponentTabActive: () => boolean;
  refreshActiveComponentTab: () => void;
  refreshComponentExplorer: () => void;
  renderComponentTree: () => void;
  setComponentGraphFocus: (nodeId: string | null, showChildren?: boolean) => void;
  currentComponentGraphFocusNode: () => unknown;
  renderComponentViews: () => void;
  zoomComponentGraphIn: () => unknown;
  zoomComponentGraphOut: () => unknown;
  resetComponentGraphViewport: () => unknown;
  clearComponentSourceOverride: () => void;
  resetComponentExplorerState: () => void;
}

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
}: ComponentDomainControllerOptions) {
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
