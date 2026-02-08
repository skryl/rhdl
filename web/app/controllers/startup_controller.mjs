export async function startApp(ctx = {}) {
  const {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    log,
    env = {},
    store = {},
    util = {},
    keys = {},
    bindings = {},
    app = {}
  } = ctx;

  const { localStorageRef = globalThis.localStorage, requestAnimationFrameImpl = globalThis.requestAnimationFrame } = env;
  const {
    setBackendState,
    setRunnerPresetState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    syncReduxUxState,
    scheduleReduxUxSync
  } = store;
  const { getBackendDef, parseNumeric, parseHexOrDec, hexByte, normalizeTheme, isSnapshotFileName } = util;
  const { SIDEBAR_COLLAPSED_KEY, TERMINAL_OPEN_KEY, THEME_KEY } = keys;
  const {
    bindCoreBindings,
    bindMemoryBindings,
    bindComponentBindings,
    bindIoBindings,
    bindSimBindings,
    bindCollapsiblePanels,
    COLLAPSIBLE_PANEL_SELECTOR,
    registerUiBinding,
    disposeUiBindings
  } = bindings;
  const { shell = {}, runner = {}, components = {}, apple2 = {}, sim = {}, watch = {} } = app;
  const { terminal = {}, dashboard = {} } = shell;

  try {
    setBackendState(getBackendDef(dom.backendSelect?.value || state.backend).id);
    if (dom.backendSelect) {
      dom.backendSelect.value = state.backend;
    }
    let collapsed = false;
    let terminalOpen = false;
    let savedTheme = 'shenzhen';
    try {
      collapsed = localStorageRef.getItem(SIDEBAR_COLLAPSED_KEY) === '1';
      terminalOpen = localStorageRef.getItem(TERMINAL_OPEN_KEY) === '1';
      savedTheme = normalizeTheme(localStorageRef.getItem(THEME_KEY) || 'shenzhen');
    } catch (_err) {
      collapsed = false;
      terminalOpen = false;
      savedTheme = 'shenzhen';
    }
    shell.setSidebarCollapsed(collapsed);
    shell.setTerminalOpen(terminalOpen, { persist: false });
    shell.applyTheme(savedTheme, { persist: false });
    await runner.ensureBackendInstance(state.backend);
    dom.simStatus.textContent = `WASM ready (${state.backend})`;
    setRunnerPresetState(dom.runnerSelect?.value || state.runnerPreset || 'apple2');
    if (dom.runnerSelect) {
      dom.runnerSelect.value = state.runnerPreset;
    }
    runner.updateIrSourceVisibility();
    shell.setActiveTab('vcdTab');
    apple2.updateIoToggleUi();
    sim.setupP5();
    const startPreset = runner.currentPreset();
    await runner.getActionsController().preloadStartPreset(startPreset);
    apple2.refreshScreen();
    apple2.refreshDebug();
    apple2.refreshMemoryView();
    if (dom.terminalOutput && !dom.terminalOutput.textContent.trim()) {
      terminal.writeLine('Terminal ready. Type "help" for commands.');
    }
  } catch (err) {
    dom.simStatus.textContent = `WASM init failed: ${err.message || err}`;
    log(`WASM init failed: ${err.message || err}`);
    return;
  }

  disposeUiBindings();
  dashboard.disposeLayoutBuilder();
  registerUiBinding(() => {
    dashboard.disposeLayoutBuilder();
  });

  registerUiBinding(bindCollapsiblePanels({
    selector: COLLAPSIBLE_PANEL_SELECTOR,
    actions: {
      refreshDashboardRowSizing: dashboard.refreshRowSizing,
      refreshAllDashboardRowSizing: dashboard.refreshAllRowSizing,
      isComponentTabActive: components.isTabActive,
      refreshActiveComponentTab: components.refreshActiveTab,
      getActiveTab: () => state.activeTab,
      refreshMemoryView: apple2.refreshMemoryView
    }
  }));
  dashboard.initializeLayoutBuilder();

  registerUiBinding(bindCoreBindings({
    dom,
    state,
    actions: {
      loadRunnerPreset: runner.loadPreset,
      setSidebarCollapsed: shell.setSidebarCollapsed,
      setTerminalOpen: shell.setTerminalOpen,
      submitTerminalInput: terminal.submitInput,
      terminalHistoryNavigate: terminal.historyNavigate,
      applyTheme: shell.applyTheme,
      getBackendDef,
      refreshStatus: sim.refreshStatus,
      setBackendState,
      ensureBackendInstance: runner.ensureBackendInstance,
      initializeSimulator: sim.initializeSimulator,
      currentRunnerPreset: runner.currentPreset,
      loadRunnerIrBundle: runner.loadBundle,
      log,
      setRunnerPresetState,
      getRunnerPreset: runner.getPreset,
      updateIrSourceVisibility: runner.updateIrSourceVisibility,
      loadSample: runner.loadSample,
      setActiveTab: shell.setActiveTab,
      refreshMemoryView: apple2.refreshMemoryView,
      refreshComponentExplorer: components.refreshExplorer
    }
  }));

  registerUiBinding(bindComponentBindings({
    dom,
    state,
    actions: {
      renderComponentTree: components.renderTree,
      scheduleReduxUxSync,
      setComponentGraphFocus: components.setGraphFocus,
      currentComponentGraphFocusNode: components.currentGraphFocusNode,
      renderComponentViews: components.renderViews,
      clearComponentSourceOverride: components.clearSourceOverride,
      resetComponentExplorerState: components.resetExplorerState,
      log,
      isComponentTabActive: components.isTabActive,
      refreshComponentExplorer: components.refreshExplorer
    }
  }));

  registerUiBinding(bindIoBindings({
    dom,
    state,
    actions: {
      setApple2DisplayHiresState,
      setApple2DisplayColorState,
      setApple2SoundEnabled: apple2.setSoundEnabled,
      updateApple2SpeakerAudio: apple2.updateSpeakerAudio,
      refreshStatus: sim.refreshStatus,
      updateIoToggleUi: apple2.updateIoToggleUi,
      refreshApple2Screen: apple2.refreshScreen,
      scheduleReduxUxSync,
      queueApple2Key: apple2.queueKey,
      isApple2UiEnabled: apple2.isUiEnabled
    }
  }));

  registerUiBinding(bindSimBindings({
    dom,
    state,
    runtime,
    actions: {
      scheduleAnimationFrame: (cb) => requestAnimationFrameImpl(cb),
      initializeSimulator: sim.initializeSimulator,
      isApple2UiEnabled: apple2.isUiEnabled,
      performApple2ResetSequence: apple2.performResetSequence,
      setRunningState,
      setCycleState,
      setUiCyclesPendingState,
      initializeTrace: sim.initializeTrace,
      refreshWatchTable: watch.refreshTable,
      refreshApple2Screen: apple2.refreshScreen,
      refreshApple2Debug: apple2.refreshDebug,
      refreshMemoryView: apple2.refreshMemoryView,
      isComponentTabActive: components.isTabActive,
      refreshActiveComponentTab: components.refreshActiveTab,
      updateApple2SpeakerAudio: apple2.updateSpeakerAudio,
      refreshStatus: sim.refreshStatus,
      log,
      stepSimulation: sim.step,
      runFrame: sim.runFrame,
      drainTrace: sim.drainTrace,
      addWatchSignal: watch.addSignal,
      removeWatchSignal: watch.removeSignal,
      parseNumeric,
      maskForWidth: sim.maskForWidth,
      breakpointAddOrReplace: (breakpoint) => appStore.dispatch(storeActions.breakpointAddOrReplace(breakpoint)),
      breakpointClear: () => appStore.dispatch(storeActions.breakpointClear()),
      breakpointRemove: (name) => appStore.dispatch(storeActions.breakpointRemove(name)),
      renderBreakpointList: watch.renderBreakpoints,
      getSignalWidth: (signal) => runtime.irMeta?.widths.get(signal) || 1
    }
  }));

  registerUiBinding(bindMemoryBindings({
    dom,
    runtime,
    actions: {
      setMemoryFollowPcState,
      refreshMemoryView: apple2.refreshMemoryView,
      scheduleReduxUxSync,
      setMemoryDumpStatus: apple2.setMemoryDumpStatus,
      loadApple2DumpOrSnapshotFile: apple2.loadDumpOrSnapshotFile,
      saveApple2MemoryDump: apple2.saveMemoryDump,
      saveApple2MemorySnapshot: apple2.saveMemorySnapshot,
      loadLastSavedApple2Dump: apple2.loadLastSavedDump,
      loadKaratekaDump: apple2.loadKaratekaDump,
      resetApple2WithMemoryVectorOverride: apple2.resetWithMemoryVectorOverride,
      isSnapshotFileName,
      parseHexOrDec,
      hexByte,
      refreshApple2Screen: apple2.refreshScreen,
      isApple2UiEnabled: apple2.isUiEnabled
    }
  }));

  syncReduxUxState('start');

  return true;
}
