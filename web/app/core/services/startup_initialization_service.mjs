function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createStartupInitializationService requires function: ${name}`);
  }
}

export function createStartupInitializationService({
  dom,
  state,
  store,
  util,
  keys,
  env,
  shell,
  runner,
  sim,
  apple2,
  terminal
} = {}) {
  if (!dom || !state) {
    throw new Error('createStartupInitializationService requires dom/state');
  }
  if (!store || !util || !keys || !env) {
    throw new Error('createStartupInitializationService requires store/util/keys/env');
  }
  if (!shell || !runner || !sim || !apple2 || !terminal) {
    throw new Error('createStartupInitializationService requires shell/runner/sim/apple2/terminal');
  }

  const { localStorageRef = globalThis.localStorage } = env;
  const { setBackendState, setRunnerPresetState } = store;
  const { getBackendDef, normalizeTheme } = util;
  const { SIDEBAR_COLLAPSED_KEY, TERMINAL_OPEN_KEY, THEME_KEY } = keys;

  requireFn('setBackendState', setBackendState);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('getBackendDef', getBackendDef);
  requireFn('normalizeTheme', normalizeTheme);
  requireFn('shell.setSidebarCollapsed', shell.setSidebarCollapsed);
  requireFn('shell.setTerminalOpen', shell.setTerminalOpen);
  requireFn('shell.applyTheme', shell.applyTheme);
  requireFn('shell.setActiveTab', shell.setActiveTab);
  requireFn('runner.ensureBackendInstance', runner.ensureBackendInstance);
  requireFn('runner.updateIrSourceVisibility', runner.updateIrSourceVisibility);
  requireFn('runner.currentPreset', runner.currentPreset);
  requireFn('runner.getActionsController', runner.getActionsController);
  requireFn('sim.setupP5', sim.setupP5);
  requireFn('apple2.updateIoToggleUi', apple2.updateIoToggleUi);
  requireFn('apple2.refreshScreen', apple2.refreshScreen);
  requireFn('apple2.refreshDebug', apple2.refreshDebug);
  requireFn('apple2.refreshMemoryView', apple2.refreshMemoryView);
  requireFn('terminal.writeLine', terminal.writeLine);

  function readSavedShellState() {
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
    return { collapsed, terminalOpen, savedTheme };
  }

  async function initialize() {
    setBackendState(getBackendDef(dom.backendSelect?.value || state.backend).id);
    if (dom.backendSelect) {
      dom.backendSelect.value = state.backend;
    }

    const { collapsed, terminalOpen, savedTheme } = readSavedShellState();
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
  }

  return {
    initialize,
    readSavedShellState
  };
}
