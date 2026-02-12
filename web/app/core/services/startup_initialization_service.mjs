import {
  DEFAULT_RUNNER_PRESET_ID,
  RUNNER_SELECT_OPTIONS,
  SAMPLE_SELECT_OPTIONS
} from '../../components/runner/config/presets.mjs';

const BACKEND_IDS = Object.freeze(['interpreter', 'compiler']);

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createStartupInitializationService requires function: ${name}`);
  }
}

function escapeHtml(value) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setSelectOptions(selectEl, options = [], preferredValue = '') {
  const normalizedOptions = Array.isArray(options)
    ? options
        .map((opt) => ({
          value: String(opt?.value || '').trim(),
          label: String(opt?.label || '').trim()
        }))
        .filter((opt) => opt.value.length > 0)
    : [];

  const values = normalizedOptions.map((opt) => opt.value);
  const fallbackValue = values[0] || '';
  const preferredToken = String(preferredValue || '').trim();
  let nextValue = preferredToken;

  if (!values.includes(nextValue)) {
    nextValue = fallbackValue;
  }

  if (!selectEl) {
    return nextValue;
  }

  const markup = normalizedOptions
    .map((opt) => `<option value=\"${escapeHtml(opt.value)}\">${escapeHtml(opt.label || opt.value)}</option>`)
    .join('');

  try {
    selectEl.innerHTML = markup;
  } catch (_err) {
    // Non-DOM test doubles may not support innerHTML assignment.
  }

  if (nextValue) {
    selectEl.value = nextValue;
  }
  return nextValue;
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
  requireFn('runner.loadPreset', runner.loadPreset);
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

  async function resolveAvailableBackends(preferredBackend = '') {
    const options = [];
    let preferredError = null;
    for (const backendId of BACKEND_IDS) {
      const backend = getBackendDef(backendId);
      if (!backend?.id) {
        continue;
      }
      try {
        await runner.ensureBackendInstance(backend.id);
        options.push({
          value: backend.id,
          label: backend.label || backend.id
        });
      } catch (err) {
        if (backend.id === preferredBackend) {
          preferredError = err;
        }
      }
    }

    if (options.length === 0) {
      if (preferredError) {
        throw preferredError;
      }
      throw new Error('No WASM backends available');
    }

    const selected = setSelectOptions(dom.backendSelect, options, preferredBackend || state.backend);
    setBackendState(selected);
    if (dom.backendSelect) {
      dom.backendSelect.value = selected;
    }
  }

  async function initialize() {
    const preferredBackend = getBackendDef(dom.backendSelect?.value || state.backend).id;
    await resolveAvailableBackends(preferredBackend);

    const { collapsed, terminalOpen, savedTheme } = readSavedShellState();
    shell.setSidebarCollapsed(collapsed);
    shell.setTerminalOpen(terminalOpen, { persist: false });
    shell.applyTheme(savedTheme, { persist: false });

    await runner.ensureBackendInstance(state.backend);
    dom.simStatus.textContent = `WASM ready (${state.backend})`;

    const initialRunnerId = setSelectOptions(
      dom.runnerSelect,
      RUNNER_SELECT_OPTIONS,
      dom.runnerSelect?.value || state.runnerPreset || DEFAULT_RUNNER_PRESET_ID
    ) || state.runnerPreset || DEFAULT_RUNNER_PRESET_ID;
    setRunnerPresetState(initialRunnerId);
    if (dom.runnerSelect) {
      dom.runnerSelect.value = initialRunnerId;
    }

    setSelectOptions(
      dom.sampleSelect,
      SAMPLE_SELECT_OPTIONS,
      dom.sampleSelect?.value || ''
    );

    runner.updateIrSourceVisibility();
    shell.setActiveTab('vcdTab');
    apple2.updateIoToggleUi();
    sim.setupP5();

    const startPreset = runner.currentPreset();
    if (startPreset?.autoLoadOnBoot) {
      await runner.loadPreset({
        presetOverride: startPreset,
        logLoad: false
      });
    } else {
      await runner.getActionsController().preloadStartPreset(startPreset);
    }

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
