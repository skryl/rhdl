export function createWatchDomainController({
  refreshWatchTable,
  addWatchSignal,
  removeWatchSignal,
  addBreakpointSignal,
  clearAllBreakpoints,
  removeBreakpointSignal,
  renderBreakpointList
}: Unsafe = {}) {
  return {
    refreshTable: refreshWatchTable,
    addSignal: addWatchSignal,
    removeSignal: removeWatchSignal,
    addBreakpoint: addBreakpointSignal,
    clearBreakpoints: clearAllBreakpoints,
    removeBreakpoint: removeBreakpointSignal,
    renderBreakpoints: renderBreakpointList
  };
}
