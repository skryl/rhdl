import type {
  StartupBindingRegistrationService,
  StartupBindingRegistrationServiceDeps,
  UnknownFn
} from '../../types/services';

type Teardown = (() => void) | null | undefined;

function requireFn(name: string, fn: unknown): asserts fn is UnknownFn {
  if (typeof fn !== 'function') {
    throw new Error(`createStartupBindingRegistrationService requires function: ${name}`);
  }
}

function toTeardown(value: unknown): Teardown {
  if (typeof value === 'function') {
    return value as () => void;
  }
  return null;
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
}: Partial<StartupBindingRegistrationServiceDeps> = {}): StartupBindingRegistrationService {
  if (!dom || !state || !runtime) {
    throw new Error('createStartupBindingRegistrationService requires dom/state/runtime');
  }
  if (!bindings || !app || !store || !util || !env) {
    throw new Error('createStartupBindingRegistrationService requires bindings/app/store/util/env');
  }
  requireFn('log', log);

  const resolvedDom = dom;
  const resolvedState = state;
  const resolvedRuntime = runtime;
  const resolvedBindings = bindings;
  const resolvedApp = app;
  const resolvedStore = store;
  const resolvedUtil = util;
  const resolvedEnv = env;

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
  } = resolvedBindings;

  const { requestAnimationFrameImpl = globalThis.requestAnimationFrame } = resolvedEnv;

  const {
    setRunnerPresetState,
    setBackendState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    setMemoryShowSourceState,
    scheduleReduxUxSync
  } = resolvedStore;

  const { getBackendDef, parseHexOrDec, hexByte, isSnapshotFileName } = resolvedUtil;

  const { shell, runner, components, apple2, sim, watch } = resolvedApp;
  const { terminal, dashboard } = shell;

  const terminalAppendInput = typeof terminal.appendInput === 'function'
    ? terminal.appendInput
    : (() => undefined);
  const terminalBackspaceInput = typeof terminal.backspaceInput === 'function'
    ? terminal.backspaceInput
    : (() => undefined);
  const terminalFocusInput = typeof terminal.focusInput === 'function'
    ? terminal.focusInput
    : (() => undefined);
  const queueApple2Key = typeof apple2.queueKey === 'function'
    ? apple2.queueKey
    : (() => undefined);

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
  requireFn('setMemoryShowSourceState', setMemoryShowSourceState);
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

  const bindCoreBindingsFn = bindCoreBindings;
  const bindMemoryBindingsFn = bindMemoryBindings;
  const bindComponentBindingsFn = bindComponentBindings;
  const bindIoBindingsFn = bindIoBindings;
  const bindSimBindingsFn = bindSimBindings;
  const bindEditorBindingsFn = bindEditorBindings;
  const bindCollapsiblePanelsFn = bindCollapsiblePanels;

  function resetBindingLifecycle() {
    disposeUiBindings();
    dashboard.disposeLayoutBuilder();
    registerUiBinding(() => {
      dashboard.disposeLayoutBuilder();
    });
  }

  function registerBindings() {
    registerUiBinding(
      toTeardown(bindCollapsiblePanelsFn({
        selector: COLLAPSIBLE_PANEL_SELECTOR,
        actions: {
          refreshDashboardRowSizing: dashboard.refreshRowSizing,
          refreshAllDashboardRowSizing: dashboard.refreshAllRowSizing,
          isComponentTabActive: components.isTabActive,
          refreshActiveComponentTab: components.refreshActiveTab,
          getActiveTab: () => resolvedState.activeTab,
          refreshMemoryView: apple2.refreshMemoryView
        }
      }))
    );
    dashboard.initializeLayoutBuilder();

    registerUiBinding(
      toTeardown(bindCoreBindingsFn({
        dom: resolvedDom,
        state: resolvedState,
        shell: {
          setSidebarCollapsed: shell.setSidebarCollapsed,
          setTerminalOpen: shell.setTerminalOpen,
          submitTerminalInput: terminal.submitInput,
          terminalHistoryNavigate: terminal.historyNavigate,
          terminalAppendInput,
          terminalBackspaceInput,
          terminalFocusInput,
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
          refreshMemoryView: apple2.refreshMemoryView,
          queueKey: queueApple2Key
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
      }))
    );

    registerUiBinding(
      toTeardown(bindComponentBindingsFn({
        dom: resolvedDom,
        state: resolvedState,
        components,
        scheduleReduxUxSync,
        log
      }))
    );

    registerUiBinding(
      toTeardown(bindIoBindingsFn({
        dom: resolvedDom,
        state: resolvedState,
        apple2,
        sim,
        store: {
          setApple2DisplayHiresState,
          setApple2DisplayColorState
        },
        scheduleReduxUxSync
      }))
    );

    registerUiBinding(
      toTeardown(bindSimBindingsFn({
        dom: resolvedDom,
        state: resolvedState,
        runtime: resolvedRuntime,
        scheduleAnimationFrame: (cb: FrameRequestCallback) => requestAnimationFrameImpl(cb),
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
      }))
    );

    registerUiBinding(
      toTeardown(bindMemoryBindingsFn({
        dom: resolvedDom,
        runtime: resolvedRuntime,
        apple2,
        store: {
          setMemoryFollowPcState,
          setMemoryShowSourceState
        },
        util: {
          isSnapshotFileName,
          parseHexOrDec,
          hexByte
        },
        scheduleReduxUxSync
      }))
    );

    registerUiBinding(
      toTeardown(bindEditorBindingsFn({
        dom: resolvedDom,
        state: resolvedState,
        runtime: resolvedRuntime,
        sim,
        watch,
        log
      }))
    );
  }

  return {
    resetBindingLifecycle,
    registerBindings
  };
}
