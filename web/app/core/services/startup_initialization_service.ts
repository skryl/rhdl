import {
  DEFAULT_RUNNER_PRESET_ID,
  RUNNER_SELECT_OPTIONS,
  SAMPLE_SELECT_OPTIONS
} from '../../components/runner/config/presets';
import type { SelectOption, ThemeId } from '../../types/models';
import type {
  StartupInitializationService,
  StartupInitializationServiceDeps,
  UnknownFn
} from '../../types/services';

const BACKEND_IDS = Object.freeze(['interpreter', 'compiler', 'arcilator']);

function requireFn(name: string, fn: unknown): asserts fn is UnknownFn {
  if (typeof fn !== 'function') {
    throw new Error(`createStartupInitializationService requires function: ${name}`);
  }
}

function escapeHtml(value: unknown) {
  return String(value || '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function setSelectOptions(
  selectEl: { value?: string; innerHTML?: string } | null,
  options: readonly SelectOption[] = [],
  preferredValue = ''
) {
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
    .map((opt) => `<option value="${escapeHtml(opt.value)}">${escapeHtml(opt.label || opt.value)}</option>`)
    .join('');

  try {
    selectEl.innerHTML = markup;
  } catch (_err: unknown) {
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
}: Partial<StartupInitializationServiceDeps> = {}): StartupInitializationService {
  if (!dom || !state) {
    throw new Error('createStartupInitializationService requires dom/state');
  }
  if (!store || !util || !keys || !env) {
    throw new Error('createStartupInitializationService requires store/util/keys/env');
  }
  if (!shell || !runner || !sim || !apple2 || !terminal) {
    throw new Error('createStartupInitializationService requires shell/runner/sim/apple2/terminal');
  }

  const resolvedDom = dom;
  const resolvedState = state;
  const resolvedStore = store;
  const resolvedUtil = util;
  const resolvedKeys = keys;
  const resolvedEnv = env;
  const resolvedShell = shell;
  const resolvedRunner = runner;
  const resolvedSim = sim;
  const resolvedApple2 = apple2;
  const resolvedTerminal = terminal;

  const { localStorageRef = globalThis.localStorage } = resolvedEnv;
  const { setBackendState, setRunnerPresetState } = resolvedStore;
  const { getBackendDef, normalizeTheme } = resolvedUtil;
  const { SIDEBAR_COLLAPSED_KEY, TERMINAL_OPEN_KEY, THEME_KEY } = resolvedKeys;

  requireFn('setBackendState', setBackendState);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('getBackendDef', getBackendDef);
  requireFn('normalizeTheme', normalizeTheme);
  requireFn('shell.setSidebarCollapsed', resolvedShell.setSidebarCollapsed);
  requireFn('shell.setTerminalOpen', resolvedShell.setTerminalOpen);
  requireFn('shell.applyTheme', resolvedShell.applyTheme);
  requireFn('shell.setActiveTab', resolvedShell.setActiveTab);
  requireFn('runner.ensureBackendInstance', resolvedRunner.ensureBackendInstance);
  requireFn('runner.loadPreset', resolvedRunner.loadPreset);
  requireFn('runner.updateIrSourceVisibility', resolvedRunner.updateIrSourceVisibility);
  requireFn('runner.currentPreset', resolvedRunner.currentPreset);
  requireFn('runner.getActionsController', resolvedRunner.getActionsController);
  requireFn('sim.setupP5', resolvedSim.setupP5);
  requireFn('apple2.updateIoToggleUi', resolvedApple2.updateIoToggleUi);
  requireFn('apple2.refreshScreen', resolvedApple2.refreshScreen);
  requireFn('apple2.refreshDebug', resolvedApple2.refreshDebug);
  requireFn('apple2.refreshMemoryView', resolvedApple2.refreshMemoryView);
  requireFn('terminal.writeLine', resolvedTerminal.writeLine);

  function readSavedShellState() {
    let collapsed = false;
    let terminalOpen = false;
    let savedTheme: ThemeId = 'shenzhen';
    try {
      collapsed = localStorageRef.getItem(SIDEBAR_COLLAPSED_KEY) === '1';
      terminalOpen = localStorageRef.getItem(TERMINAL_OPEN_KEY) === '1';
      savedTheme = normalizeTheme(localStorageRef.getItem(THEME_KEY) || 'shenzhen');
    } catch (_err: unknown) {
      collapsed = false;
      terminalOpen = false;
      savedTheme = 'shenzhen';
    }
    return { collapsed, terminalOpen, savedTheme };
  }

  async function resolveAvailableBackends(preferredBackend = '') {
    const options: SelectOption[] = [];
    for (const backendId of BACKEND_IDS) {
      const backend = getBackendDef(backendId);
      if (!backend?.id) {
        continue;
      }
      options.push({
        value: backend.id,
        label: backend.label || backend.id
      });
    }

    if (options.length === 0) {
      throw new Error('No WASM backends available');
    }

    let selected = setSelectOptions(resolvedDom.backendSelect, options, preferredBackend || resolvedState.backend);
    setBackendState(selected);
    if (resolvedDom.backendSelect && resolvedDom.backendSelect.value !== selected) {
      resolvedDom.backendSelect.value = selected;
    }

    try {
      await resolvedRunner.ensureBackendInstance(selected);
    } catch (err: unknown) {
      const fallback = options.find((opt) => opt.value === 'interpreter')?.value || options[0]?.value || selected;
      if (fallback === selected) {
        throw err;
      }
      selected = setSelectOptions(resolvedDom.backendSelect, options, fallback);
      setBackendState(selected);
      if (resolvedDom.backendSelect && resolvedDom.backendSelect.value !== selected) {
        resolvedDom.backendSelect.value = selected;
      }
      await resolvedRunner.ensureBackendInstance(selected);
    }
  }

  async function initialize() {
    const preferredBackend = getBackendDef(resolvedDom.backendSelect?.value || resolvedState.backend).id;
    await resolveAvailableBackends(preferredBackend);

    const { collapsed, terminalOpen, savedTheme } = readSavedShellState();
    resolvedShell.setSidebarCollapsed(collapsed);
    resolvedShell.setTerminalOpen(terminalOpen, { persist: false });
    resolvedShell.applyTheme(savedTheme, { persist: false });

    if (resolvedDom.simStatus) {
      resolvedDom.simStatus.textContent = `WASM ready (${resolvedState.backend})`;
    }

    const initialRunnerId = setSelectOptions(
      resolvedDom.runnerSelect,
      RUNNER_SELECT_OPTIONS,
      resolvedDom.runnerSelect?.value || resolvedState.runnerPreset || DEFAULT_RUNNER_PRESET_ID
    ) || resolvedState.runnerPreset || DEFAULT_RUNNER_PRESET_ID;
    setRunnerPresetState(initialRunnerId);
    if (resolvedDom.runnerSelect) {
      resolvedDom.runnerSelect.value = initialRunnerId;
    }

    setSelectOptions(
      resolvedDom.sampleSelect,
      SAMPLE_SELECT_OPTIONS,
      resolvedDom.sampleSelect?.value || ''
    );

    resolvedRunner.updateIrSourceVisibility();
    resolvedShell.setActiveTab('vcdTab');
    resolvedApple2.updateIoToggleUi();
    resolvedSim.setupP5();

    const startPreset = resolvedRunner.currentPreset();
    if (startPreset?.autoLoadOnBoot) {
      await resolvedRunner.loadPreset({
        presetOverride: startPreset,
        logLoad: false
      });
    } else {
      await resolvedRunner.getActionsController().preloadStartPreset(startPreset);
    }

    resolvedApple2.refreshScreen();
    resolvedApple2.refreshDebug();
    resolvedApple2.refreshMemoryView();

    const terminalText = String(
      resolvedDom.terminalOutput?.dataset?.terminalText
      ?? resolvedDom.terminalOutput?.value
      ?? resolvedDom.terminalOutput?.textContent
      ?? ''
    ).trim();
    if (resolvedDom.terminalOutput && (!terminalText || terminalText === '$')) {
      resolvedTerminal.writeLine('Terminal ready. Type "help" for commands.');
    }
  }

  return {
    initialize,
    readSavedShellState
  };
}
