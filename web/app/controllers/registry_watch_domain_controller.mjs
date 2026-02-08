export function createWatchDomainController({
  refreshWatchTable,
  addWatchSignal,
  removeWatchSignal,
  renderBreakpointList
} = {}) {
  return {
    refreshTable: refreshWatchTable,
    addSignal: addWatchSignal,
    removeSignal: removeWatchSignal,
    renderBreakpoints: renderBreakpointList
  };
}
