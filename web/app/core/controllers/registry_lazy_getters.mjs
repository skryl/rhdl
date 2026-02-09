import { createWatchLazyGetters } from '../../components/watch/controllers/lazy_getters.mjs';
import { createComponentLazyGetters } from '../../components/explorer/controllers/lazy_getters.mjs';
import { createRunnerLazyGetters } from '../../components/runner/controllers/lazy_getters.mjs';
import { createApple2LazyGetters } from '../../components/apple2/controllers/lazy_getters.mjs';
import { createSimLazyGetters } from '../../components/sim/controllers/lazy_getters.mjs';
import { createShellLazyGetters } from '../../components/shell/controllers/lazy_getters.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createRegistryLazyGetters requires function: ${name}`);
  }
}

export function createRegistryLazyGetters(options = {}) {
  const {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    scheduleReduxUxSync,
    log,
    setRunnerPresetState,
    setActiveTabState,
    setSidebarCollapsedState,
    setTerminalOpenState,
    setThemeState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    setMemoryDumpStatus,
    setMemoryResetVectorInput,
    setApple2SoundEnabledState,
    replaceBreakpointsState,
    setActiveTab,
    setSidebarCollapsed,
    setTerminalOpen,
    applyTheme,
    updateIrSourceVisibility,
    loadRunnerPreset,
    loadRunnerIrBundle,
    initializeSimulator,
    applyRunnerDefaults,
    clearComponentSourceOverride,
    resetComponentExplorerState,
    clearComponentSourceBundle,
    clearComponentSchematicBundle,
    setComponentSourceBundle,
    setComponentSchematicBundle,
    refreshComponentExplorer,
    isComponentTabActive,
    refreshActiveComponentTab,
    currentRunnerPreset,
    getRunnerPreset,
    currentComponentSourceText,
    destroyComponentGraph,
    refreshStatus,
    stepSimulation,
    addWatchSignal,
    removeWatchSignal,
    clearAllWatches,
    addBreakpointSignal,
    clearAllBreakpoints,
    renderBreakpointList,
    refreshWatchTable,
    checkBreakpoints,
    selectedClock,
    maskForWidth,
    populateClockSelect,
    initializeTrace,
    renderWatchList,
    refreshApple2Screen,
    refreshApple2Debug,
    refreshMemoryView,
    updateApple2SpeakerAudio,
    isApple2UiEnabled,
    updateIoToggleUi,
    apple2HiresLineAddress,
    getApple2ProgramCounter,
    ensureBackendInstance,
    rebuildComponentExplorer,
    setComponentSourceOverride,
    loadSample,
    resetApple2WithMemoryVectorOverride,
    loadKaratekaDump,
    loadLastSavedApple2Dump,
    saveApple2MemoryDump,
    saveApple2MemorySnapshot,
    queueApple2Key,
    refreshAllDashboardRowSizing,
    drainTrace,
    fetchImpl = globalThis.fetch,
    webAssemblyApi = globalThis.WebAssembly,
    requestFrame = globalThis.requestAnimationFrame,
    windowRef = globalThis.window,
    documentRef = globalThis.document,
    localStorageRef = globalThis.localStorage,
    eventCtor = globalThis.Event
  } = options;

  if (!dom || !state || !runtime || !appStore || !storeActions) {
    throw new Error('createRegistryLazyGetters requires dom/state/runtime/appStore/storeActions');
  }

  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('log', log);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('setActiveTabState', setActiveTabState);
  requireFn('setSidebarCollapsedState', setSidebarCollapsedState);
  requireFn('setTerminalOpenState', setTerminalOpenState);
  requireFn('setThemeState', setThemeState);
  requireFn('setRunningState', setRunningState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('setMemoryResetVectorInput', setMemoryResetVectorInput);
  requireFn('setApple2SoundEnabledState', setApple2SoundEnabledState);
  requireFn('replaceBreakpointsState', replaceBreakpointsState);
  requireFn('setActiveTab', setActiveTab);
  requireFn('setSidebarCollapsed', setSidebarCollapsed);
  requireFn('setTerminalOpen', setTerminalOpen);
  requireFn('applyTheme', applyTheme);
  requireFn('updateIrSourceVisibility', updateIrSourceVisibility);
  requireFn('loadRunnerPreset', loadRunnerPreset);
  requireFn('loadRunnerIrBundle', loadRunnerIrBundle);
  requireFn('initializeSimulator', initializeSimulator);
  requireFn('applyRunnerDefaults', applyRunnerDefaults);
  requireFn('clearComponentSourceOverride', clearComponentSourceOverride);
  requireFn('resetComponentExplorerState', resetComponentExplorerState);
  requireFn('clearComponentSourceBundle', clearComponentSourceBundle);
  requireFn('clearComponentSchematicBundle', clearComponentSchematicBundle);
  requireFn('setComponentSourceBundle', setComponentSourceBundle);
  requireFn('setComponentSchematicBundle', setComponentSchematicBundle);
  requireFn('refreshComponentExplorer', refreshComponentExplorer);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshActiveComponentTab', refreshActiveComponentTab);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('getRunnerPreset', getRunnerPreset);
  requireFn('currentComponentSourceText', currentComponentSourceText);
  requireFn('destroyComponentGraph', destroyComponentGraph);
  requireFn('refreshStatus', refreshStatus);
  requireFn('stepSimulation', stepSimulation);
  requireFn('addWatchSignal', addWatchSignal);
  requireFn('removeWatchSignal', removeWatchSignal);
  requireFn('clearAllWatches', clearAllWatches);
  requireFn('addBreakpointSignal', addBreakpointSignal);
  requireFn('clearAllBreakpoints', clearAllBreakpoints);
  requireFn('renderBreakpointList', renderBreakpointList);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('checkBreakpoints', checkBreakpoints);
  requireFn('selectedClock', selectedClock);
  requireFn('maskForWidth', maskForWidth);
  requireFn('populateClockSelect', populateClockSelect);
  requireFn('initializeTrace', initializeTrace);
  requireFn('renderWatchList', renderWatchList);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('updateApple2SpeakerAudio', updateApple2SpeakerAudio);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('apple2HiresLineAddress', apple2HiresLineAddress);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('ensureBackendInstance', ensureBackendInstance);
  requireFn('rebuildComponentExplorer', rebuildComponentExplorer);
  requireFn('setComponentSourceOverride', setComponentSourceOverride);
  requireFn('loadSample', loadSample);
  requireFn('resetApple2WithMemoryVectorOverride', resetApple2WithMemoryVectorOverride);
  requireFn('loadKaratekaDump', loadKaratekaDump);
  requireFn('loadLastSavedApple2Dump', loadLastSavedApple2Dump);
  requireFn('saveApple2MemoryDump', saveApple2MemoryDump);
  requireFn('saveApple2MemorySnapshot', saveApple2MemorySnapshot);
  requireFn('queueApple2Key', queueApple2Key);
  requireFn('refreshAllDashboardRowSizing', refreshAllDashboardRowSizing);
  requireFn('drainTrace', drainTrace);
  requireFn('fetchImpl', fetchImpl);

  const watchGetters = createWatchLazyGetters({
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    scheduleReduxUxSync,
    log,
    maskForWidth
  });

  const componentGetters = createComponentLazyGetters({
    dom,
    state,
    runtime,
    scheduleReduxUxSync,
    currentComponentSourceText,
    currentRunnerPreset,
    destroyComponentGraph
  });

  const runnerGetters = createRunnerLazyGetters({
    dom,
    state,
    setRunnerPresetState,
    fetchImpl,
    log,
    getRunnerPreset,
    updateIrSourceVisibility,
    loadRunnerIrBundle,
    initializeSimulator,
    applyRunnerDefaults,
    clearComponentSourceOverride,
    resetComponentExplorerState,
    isComponentTabActive,
    refreshComponentExplorer,
    clearComponentSourceBundle,
    clearComponentSchematicBundle,
    setComponentSourceBundle,
    setComponentSchematicBundle,
    setActiveTab,
    refreshStatus
  });

  const apple2Getters = createApple2LazyGetters({
    dom,
    state,
    runtime,
    setApple2SoundEnabledState,
    setMemoryFollowPcState,
    setCycleState,
    setUiCyclesPendingState,
    setRunningState,
    fetchImpl,
    windowRef,
    documentRef,
    log,
    isApple2UiEnabled,
    setMemoryDumpStatus,
    updateIoToggleUi,
    apple2HiresLineAddress,
    refreshApple2Screen,
    refreshApple2Debug,
    refreshMemoryView,
    refreshWatchTable,
    refreshStatus,
    getApple2ProgramCounter,
    currentRunnerPreset
  });

  const simGetters = createSimLazyGetters({
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    scheduleReduxUxSync,
    setRunnerPresetState,
    setCycleState,
    setUiCyclesPendingState,
    setRunningState,
    fetchImpl,
    webAssemblyApi,
    requestFrame,
    log,
    getRunnerPreset,
    setComponentSourceBundle,
    setComponentSchematicBundle,
    ensureBackendInstance,
    updateApple2SpeakerAudio,
    setMemoryDumpStatus,
    setMemoryResetVectorInput,
    initializeTrace,
    populateClockSelect,
    addWatchSignal,
    selectedClock,
    renderWatchList,
    renderBreakpointList,
    refreshWatchTable,
    refreshApple2Screen,
    refreshApple2Debug,
    refreshMemoryView,
    setComponentSourceOverride,
    clearComponentSourceOverride,
    rebuildComponentExplorer,
    refreshStatus,
    currentRunnerPreset,
    isApple2UiEnabled,
    updateIoToggleUi,
    checkBreakpoints,
    isComponentTabActive,
    refreshActiveComponentTab,
    drainTrace
  });

  const shellGetters = createShellLazyGetters({
    dom,
    state,
    runtime,
    scheduleReduxUxSync,
    setRunnerPresetState,
    setActiveTabState,
    setSidebarCollapsedState,
    setTerminalOpenState,
    setThemeState,
    setMemoryFollowPcState,
    replaceBreakpointsState,
    requestFrame,
    windowRef,
    documentRef,
    localStorageRef,
    eventCtor,
    currentRunnerPreset,
    setSidebarCollapsed,
    setTerminalOpen,
    setActiveTab,
    updateIrSourceVisibility,
    loadRunnerPreset,
    refreshStatus,
    applyTheme,
    loadSample,
    initializeSimulator,
    stepSimulation,
    addWatchSignal,
    removeWatchSignal,
    clearAllWatches,
    addBreakpointSignal,
    clearAllBreakpoints,
    renderBreakpointList,
    refreshMemoryView,
    resetApple2WithMemoryVectorOverride,
    loadKaratekaDump,
    loadLastSavedApple2Dump,
    saveApple2MemoryDump,
    saveApple2MemorySnapshot,
    queueApple2Key,
    refreshAllDashboardRowSizing,
    refreshComponentExplorer,
    isComponentTabActive,
    refreshActiveComponentTab
  });

  return {
    ...watchGetters,
    ...componentGetters,
    ...runnerGetters,
    ...apple2Getters,
    ...simGetters,
    ...shellGetters
  };
}
