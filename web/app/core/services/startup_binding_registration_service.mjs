function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createStartupBindingRegistrationService requires function: ${name}`);
  }
}

export function createStartupBindingRegistrationService({
  dom,
  state,
  runtime,
  bindings,
  app,
  store,
  util,
  env,
  log
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createStartupBindingRegistrationService requires dom/state/runtime');
  }
  if (!bindings || !app || !store || !util || !env) {
    throw new Error('createStartupBindingRegistrationService requires bindings/app/store/util/env');
  }
  requireFn('log', log);

  const {
    bindCoreBindings,
    bindMemoryBindings,
    bindComponentBindings,
    bindIoBindings,
    bindSimBindings,
    bindEditorBindings,
    bindCollapsiblePanels,
    COLLAPSIBLE_PANEL_SELECTOR,
    registerUiBinding,
    disposeUiBindings
  } = bindings;

  const { requestAnimationFrameImpl = globalThis.requestAnimationFrame } = env;

  const {
    setRunnerPresetState,
    setBackendState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    scheduleReduxUxSync
  } = store;

  const { getBackendDef, parseHexOrDec, hexByte, isSnapshotFileName } = util;

  const { shell = {}, runner = {}, components = {}, apple2 = {}, sim = {}, watch = {} } = app;
  const { terminal = {}, dashboard = {} } = shell;

  requireFn('bindCoreBindings', bindCoreBindings);
  requireFn('bindMemoryBindings', bindMemoryBindings);
  requireFn('bindComponentBindings', bindComponentBindings);
  requireFn('bindIoBindings', bindIoBindings);
  requireFn('bindSimBindings', bindSimBindings);
  requireFn('bindEditorBindings', bindEditorBindings);
  requireFn('bindCollapsiblePanels', bindCollapsiblePanels);
  requireFn('registerUiBinding', registerUiBinding);
  requireFn('disposeUiBindings', disposeUiBindings);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('setBackendState', setBackendState);
  requireFn('setApple2DisplayHiresState', setApple2DisplayHiresState);
  requireFn('setApple2DisplayColorState', setApple2DisplayColorState);
  requireFn('setRunningState', setRunningState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('getBackendDef', getBackendDef);
  requireFn('parseHexOrDec', parseHexOrDec);
  requireFn('hexByte', hexByte);
  requireFn('isSnapshotFileName', isSnapshotFileName);
  requireFn('dashboard.disposeLayoutBuilder', dashboard.disposeLayoutBuilder);
  requireFn('dashboard.initializeLayoutBuilder', dashboard.initializeLayoutBuilder);
  requireFn('dashboard.refreshRowSizing', dashboard.refreshRowSizing);
  requireFn('dashboard.refreshAllRowSizing', dashboard.refreshAllRowSizing);
  requireFn('components.isTabActive', components.isTabActive);
  requireFn('components.refreshActiveTab', components.refreshActiveTab);
  requireFn('components.refreshExplorer', components.refreshExplorer);
  requireFn('apple2.refreshMemoryView', apple2.refreshMemoryView);
  requireFn('shell.setSidebarCollapsed', shell.setSidebarCollapsed);
  requireFn('shell.setTerminalOpen', shell.setTerminalOpen);
  requireFn('shell.applyTheme', shell.applyTheme);
  requireFn('shell.setActiveTab', shell.setActiveTab);
  requireFn('terminal.submitInput', terminal.submitInput);
  requireFn('terminal.historyNavigate', terminal.historyNavigate);
  requireFn('runner.loadPreset', runner.loadPreset);
  requireFn('runner.ensureBackendInstance', runner.ensureBackendInstance);
  requireFn('runner.currentPreset', runner.currentPreset);
  requireFn('runner.loadBundle', runner.loadBundle);
  requireFn('runner.getPreset', runner.getPreset);
  requireFn('runner.updateIrSourceVisibility', runner.updateIrSourceVisibility);
  requireFn('runner.loadSample', runner.loadSample);
  requireFn('sim.refreshStatus', sim.refreshStatus);
  requireFn('sim.initializeSimulator', sim.initializeSimulator);

  function resetBindingLifecycle() {
    disposeUiBindings();
    dashboard.disposeLayoutBuilder();
    registerUiBinding(() => {
      dashboard.disposeLayoutBuilder();
    });
  }

  function registerBindings() {
    registerUiBinding(
      bindCollapsiblePanels({
        selector: COLLAPSIBLE_PANEL_SELECTOR,
        actions: {
          refreshDashboardRowSizing: dashboard.refreshRowSizing,
          refreshAllDashboardRowSizing: dashboard.refreshAllRowSizing,
          isComponentTabActive: components.isTabActive,
          refreshActiveComponentTab: components.refreshActiveTab,
          getActiveTab: () => state.activeTab,
          refreshMemoryView: apple2.refreshMemoryView
        }
      })
    );
    dashboard.initializeLayoutBuilder();

    registerUiBinding(
      bindCoreBindings({
        dom,
        state,
        shell: {
          setSidebarCollapsed: shell.setSidebarCollapsed,
          setTerminalOpen: shell.setTerminalOpen,
          submitTerminalInput: terminal.submitInput,
          terminalHistoryNavigate: terminal.historyNavigate,
          terminalAppendInput: terminal.appendInput || (() => {}),
          terminalBackspaceInput: terminal.backspaceInput || (() => {}),
          terminalFocusInput: terminal.focusInput || (() => {}),
          applyTheme: shell.applyTheme,
          setActiveTab: shell.setActiveTab
        },
        runner: {
          loadPreset: runner.loadPreset,
          ensureBackendInstance: runner.ensureBackendInstance,
          currentPreset: runner.currentPreset,
          loadBundle: runner.loadBundle,
          getPreset: runner.getPreset,
          updateIrSourceVisibility: runner.updateIrSourceVisibility,
          loadSample: runner.loadSample
        },
        sim: {
          refreshStatus: sim.refreshStatus,
          initializeSimulator: sim.initializeSimulator
        },
        apple2: {
          refreshMemoryView: apple2.refreshMemoryView
        },
        components: {
          refreshExplorer: components.refreshExplorer
        },
        store: {
          setBackendState,
          setRunnerPresetState
        },
        util: {
          getBackendDef
        },
        log
      })
    );

    registerUiBinding(
      bindComponentBindings({
        dom,
        state,
        components,
        scheduleReduxUxSync,
        log
      })
    );

    registerUiBinding(
      bindIoBindings({
        dom,
        state,
        apple2,
        sim,
        store: {
          setApple2DisplayHiresState,
          setApple2DisplayColorState
        },
        scheduleReduxUxSync
      })
    );

    registerUiBinding(
      bindSimBindings({
        dom,
        state,
        runtime,
        scheduleAnimationFrame: (cb) => requestAnimationFrameImpl(cb),
        sim,
        apple2,
        components,
        watch,
        store: {
          setRunningState,
          setCycleState,
          setUiCyclesPendingState
        },
        log
      })
    );

    registerUiBinding(
      bindMemoryBindings({
        dom,
        runtime,
        apple2,
        store: {
          setMemoryFollowPcState
        },
        util: {
          isSnapshotFileName,
          parseHexOrDec,
          hexByte
        },
        scheduleReduxUxSync
      })
    );

    registerUiBinding(
      bindEditorBindings({
        dom,
        state,
        runtime,
        sim,
        watch,
        log
      })
    );
  }

  return {
    resetBindingLifecycle,
    registerBindings
  };
}
