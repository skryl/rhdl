export function createStartupContext(options = {}) {
  const {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    localStorageRef,
    requestAnimationFrameImpl,
    setBackendState,
    getBackendDef,
    setRunnerPresetState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    syncReduxUxState,
    scheduleReduxUxSync,
    parseNumeric,
    parseHexOrDec,
    hexByte,
    normalizeTheme,
    isSnapshotFileName,
    SIDEBAR_COLLAPSED_KEY,
    TERMINAL_OPEN_KEY,
    THEME_KEY,
    bindCoreBindings,
    bindMemoryBindings,
    bindComponentBindings,
    bindIoBindings,
    bindSimBindings,
    bindCollapsiblePanels,
    COLLAPSIBLE_PANEL_SELECTOR,
    registerUiBinding,
    disposeUiBindings,
    log,
    controllers = {}
  } = options;

  return {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    log,
    env: {
      localStorageRef,
      requestAnimationFrameImpl
    },
    store: {
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
    },
    util: {
      getBackendDef,
      parseNumeric,
      parseHexOrDec,
      hexByte,
      normalizeTheme,
      isSnapshotFileName
    },
    keys: {
      SIDEBAR_COLLAPSED_KEY,
      TERMINAL_OPEN_KEY,
      THEME_KEY
    },
    bindings: {
      bindCoreBindings,
      bindMemoryBindings,
      bindComponentBindings,
      bindIoBindings,
      bindSimBindings,
      bindCollapsiblePanels,
      COLLAPSIBLE_PANEL_SELECTOR,
      registerUiBinding,
      disposeUiBindings
    },
    app: {
      shell: controllers.shell || {},
      runner: controllers.runner || {},
      components: controllers.components || {},
      apple2: controllers.apple2 || {},
      sim: controllers.sim || {},
      watch: controllers.watch || {}
    }
  };
}
