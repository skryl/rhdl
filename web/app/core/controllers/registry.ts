import { RUNNER_PRESETS } from '../../components/runner/config/presets';
import { formatValue } from '../lib/numeric_utils';
import { waveformFontFamily, waveformPalette } from '../lib/theme_utils';
import { setupWaveformP5 } from '../../components/watch/ui/waveform_panel';
import { createRegistryLazyGetters } from './registry_lazy_getters';
import { createShellDomainController } from '../../components/shell/controllers/domain';
import { createRunnerDomainController } from '../../components/runner/controllers/domain';
import { createComponentDomainController } from '../../components/explorer/controllers/domain';
import { createApple2DomainController } from '../../components/apple2/controllers/domain';
import { createSimDomainController } from '../../components/sim/controllers/domain';
import { createWatchDomainController } from '../../components/watch/controllers/domain';
import { resolveRunnerIoConfig } from '../../components/runner/lib/io_config';

function normalizePositiveInt(value: any, fallback = null) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function formatMemoryAddress(value: any) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return '';
  }
  const masked = Math.max(0, parsed);
  const width = masked > 0xFFFF ? 8 : 4;
  return `0x${Math.floor(masked).toString(16).toUpperCase().padStart(width, '0')}`;
}

export function createControllerRegistry(options: any = {}) {
  const {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    scheduleReduxUxSync,
    log,
    setBackendState,
    setRunnerPresetState,
    setActiveTabState,
    setSidebarCollapsedState,
    setTerminalOpenState,
    setThemeState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setApple2SoundEnabledState,
    replaceBreakpointsState,
    fetchImpl = globalThis.fetch,
    webAssemblyApi = globalThis.WebAssembly,
    requestFrame = globalThis.requestAnimationFrame,
    windowRef = globalThis.window,
    documentRef = globalThis.document,
    localStorageRef = globalThis.localStorage,
    eventCtor = globalThis.Event,
    p5Ctor = (globalThis as any).p5
  } = options;

  const lazy = createRegistryLazyGetters({
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    scheduleReduxUxSync,
    log,
    setBackendState,
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
    fetchImpl,
    webAssemblyApi,
    requestFrame,
    windowRef,
    documentRef,
    localStorageRef,
    eventCtor
  });

  function terminalWriteLine(message = '') {
    lazy.getTerminalController().writeLine(message);
  }

  function clearAllWatches() {
    lazy.getWatchManager().clearAllWatches();
  }

  function addBreakpointSignal(signal: any, valueRaw: any) {
    return lazy.getWatchManager().addBreakpointSignal(signal, valueRaw);
  }

  function clearAllBreakpoints() {
    lazy.getWatchManager().clearAllBreakpoints();
  }

  function removeBreakpointSignal(name: any) {
    const key = String(name || '').trim();
    if (!key) {
      return false;
    }
    const nextBreakpoints = state.breakpoints.filter((bp: any) => String(bp?.name || '') !== key);
    if (nextBreakpoints.length === state.breakpoints.length) {
      return false;
    }
    replaceBreakpointsState(nextBreakpoints);
    renderBreakpointList();
    return true;
  }

  async function submitTerminalInput() {
    return lazy.getTerminalController().submitInput();
  }

  function terminalHistoryNavigate(delta: any) {
    return lazy.getTerminalController().historyNavigate(delta);
  }

  function terminalAppendInput(text = '') {
    return lazy.getTerminalController().appendInput(text);
  }

  function terminalBackspaceInput() {
    return lazy.getTerminalController().backspaceInput();
  }

  function terminalSetInput(text = '') {
    return lazy.getTerminalController().setInput(text);
  }

  function terminalFocusInput() {
    return lazy.getTerminalController().focusInput();
  }

  function getRunnerPreset(id: any) {
    if (id && RUNNER_PRESETS[id]) {
      return RUNNER_PRESETS[id];
    }
    return RUNNER_PRESETS.generic;
  }

  function currentRunnerPreset() {
    return getRunnerPreset(state.runnerPreset);
  }

  function setComponentSourceOverride(source = '', meta = null) {
    lazy.getComponentSourceController().setComponentSourceOverride(source, meta);
  }

  function clearComponentSourceOverride() {
    lazy.getComponentSourceController().clearComponentSourceOverride();
  }

  function resetComponentExplorerState() {
    lazy.getComponentSourceController().resetComponentExplorerState();
  }

  function currentComponentSourceText() {
    return lazy.getComponentSourceController().currentComponentSourceText();
  }

  function updateIrSourceVisibility() {
    lazy.getComponentSourceController().updateIrSourceVisibility();
  }

  function clearComponentSourceBundle() {
    lazy.getComponentSourceController().clearComponentSourceBundle();
  }

  function setComponentSourceBundle(bundle: any) {
    lazy.getComponentSourceController().setComponentSourceBundle(bundle);
  }

  function clearComponentSchematicBundle() {
    lazy.getComponentSourceController().clearComponentSchematicBundle();
  }

  function setComponentSchematicBundle(bundle: any) {
    lazy.getComponentSourceController().setComponentSchematicBundle(bundle);
  }

  async function loadRunnerIrBundle(preset: any, options = {}) {
    return lazy.getRunnerBundleLoader().loadRunnerIrBundle(preset, options);
  }

  async function applyRunnerDefaults(preset: any) {
    const ioConfig = resolveRunnerIoConfig(preset);
    const defaults = preset?.defaults && typeof preset.defaults === 'object'
      ? preset.defaults
      : {};

    if (Object.prototype.hasOwnProperty.call(defaults, 'displayHires')) {
      setApple2DisplayHiresState(!!defaults.displayHires);
    }
    if (Object.prototype.hasOwnProperty.call(defaults, 'displayColor')) {
      setApple2DisplayColorState(!!defaults.displayColor);
    }
    if (Object.prototype.hasOwnProperty.call(defaults, 'memoryFollowPc')) {
      setMemoryFollowPcState(!!defaults.memoryFollowPc);
    }
    if (dom.stepTicks && Object.prototype.hasOwnProperty.call(defaults, 'stepTicks')) {
      const value = normalizePositiveInt(defaults.stepTicks);
      if (value != null) {
        dom.stepTicks.value = String(value);
      }
    }
    if (dom.runBatch && Object.prototype.hasOwnProperty.call(defaults, 'runBatch')) {
      const value = normalizePositiveInt(defaults.runBatch);
      if (value != null) {
        dom.runBatch.value = String(value);
      }
    }
    if (dom.uiUpdateCycles && Object.prototype.hasOwnProperty.call(defaults, 'uiUpdateCycles')) {
      const value = normalizePositiveInt(defaults.uiUpdateCycles);
      if (value != null) {
        dom.uiUpdateCycles.value = String(value);
      }
    }
    if (dom.memoryStart && ioConfig?.memory) {
      const dumpStart = Number.parseInt(ioConfig.memory.dumpStart as any, 10);
      if (Number.isFinite(dumpStart)) {
        dom.memoryStart.value = formatMemoryAddress(dumpStart);
      }
    }
    if (dom.memoryLength && ioConfig?.memory) {
      const dumpLength = Number.parseInt(ioConfig.memory.dumpLength as any, 10);
      if (Number.isFinite(dumpLength)) {
        dom.memoryLength.value = String(dumpLength);
      }
    }

    if (!ioConfig.enabled) {
      return;
    }

    updateIoToggleUi();
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();

    if (defaults.loadKaratekaDumpOnLoad && ioConfig.api === 'apple2') {
      await loadKaratekaDump();
    }
  }

  function setActiveTab(tabId: any) {
    lazy.getShellStateController().setActiveTab(tabId);
  }

  function setSidebarCollapsed(collapsed: any) {
    lazy.getShellStateController().setSidebarCollapsed(collapsed);
  }

  function setTerminalOpen(open: any, { persist = true, focus = false }: any = {}) {
    lazy.getShellStateController().setTerminalOpen(open, { persist, focus });
  }

  function getDashboardLayoutManager() {
    return lazy.getDashboardLayoutController().getDashboardLayoutManager();
  }

  function disposeDashboardLayoutBuilder() {
    lazy.getDashboardLayoutController().disposeDashboardLayoutBuilder();
  }

  function refreshDashboardRowSizing(rootKey: any) {
    lazy.getDashboardLayoutController().refreshDashboardRowSizing(rootKey);
  }

  function refreshAllDashboardRowSizing() {
    lazy.getDashboardLayoutController().refreshAllDashboardRowSizing();
  }

  function initializeDashboardLayoutBuilder() {
    lazy.getDashboardLayoutController().initializeDashboardLayoutBuilder();
  }

  function applyTheme(theme: any, { persist = true }: any = {}) {
    lazy.getShellStateController().applyTheme(theme, { persist });
  }

  function ensureComponentSelection() {
    lazy.getComponentExplorerController().ensureComponentSelection();
  }

  function ensureComponentGraphFocus() {
    lazy.getComponentExplorerController().ensureComponentGraphFocus();
  }

  function currentComponentGraphFocusNode() {
    return lazy.getComponentExplorerController().currentComponentGraphFocusNode();
  }

  function setComponentGraphFocus(nodeId: any, showChildren = true) {
    lazy.getComponentExplorerController().setComponentGraphFocus(nodeId, showChildren);
  }

  function renderComponentTree() {
    lazy.getComponentExplorerController().renderComponentTree();
  }

  function currentSelectedComponentNode() {
    return lazy.getComponentExplorerController().currentSelectedComponentNode();
  }

  function isComponentTabActive() {
    return lazy.getComponentExplorerController().isComponentTabActive();
  }

  function renderComponentViews() {
    lazy.getComponentExplorerController().renderComponentViews();
  }

  function refreshActiveComponentTab() {
    lazy.getComponentExplorerController().refreshActiveComponentTab();
  }

  function destroyComponentGraph() {
    lazy.getComponentExplorerController().destroyComponentGraph();
  }

  function zoomComponentGraphIn() {
    return lazy.getComponentExplorerController().zoomComponentGraphIn();
  }

  function zoomComponentGraphOut() {
    return lazy.getComponentExplorerController().zoomComponentGraphOut();
  }

  function resetComponentGraphViewport() {
    return lazy.getComponentExplorerController().resetComponentGraphViewport();
  }

  function rebuildComponentExplorer(meta = runtime.irMeta, source = currentComponentSourceText()) {
    lazy.getComponentExplorerController().rebuildComponentExplorer(meta, source);
  }

  function refreshComponentExplorer() {
    lazy.getComponentExplorerController().refreshComponentExplorer();
  }

  function isApple2UiEnabled() {
    return lazy.getApple2OpsController().isApple2UiEnabled();
  }

  function updateIoToggleUi() {
    lazy.getApple2OpsController().updateIoToggleUi();
  }

  function apple2HiresLineAddress(row: any) {
    return lazy.getApple2OpsController().apple2HiresLineAddress(row);
  }

  async function setApple2SoundEnabled(enabled: any) {
    return lazy.getApple2OpsController().setApple2SoundEnabled(enabled);
  }

  function updateApple2SpeakerAudio(toggles: any, cyclesRun: any) {
    lazy.getApple2OpsController().updateApple2SpeakerAudio(toggles, cyclesRun);
  }

  function setMemoryDumpStatus(message: any) {
    lazy.getApple2OpsController().setMemoryDumpStatus(message);
  }

  function setMemoryResetVectorInput(value: any) {
    lazy.getApple2OpsController().setMemoryResetVectorInput(value);
  }

  async function saveApple2MemoryDump() {
    return lazy.getApple2OpsController().saveApple2MemoryDump();
  }

  async function saveApple2MemorySnapshot() {
    return lazy.getApple2OpsController().saveApple2MemorySnapshot();
  }

  async function loadApple2DumpOrSnapshotFile(file: any, offsetRaw: any) {
    return lazy.getApple2OpsController().loadApple2DumpOrSnapshotFile(file, offsetRaw);
  }

  async function loadApple2DumpOrSnapshotAssetPath(assetPath: any, offsetRaw: any) {
    return lazy.getApple2OpsController().loadApple2DumpOrSnapshotAssetPath(assetPath, offsetRaw);
  }

  async function loadLastSavedApple2Dump() {
    return lazy.getApple2OpsController().loadLastSavedApple2Dump();
  }

  async function resetApple2WithMemoryVectorOverride() {
    return lazy.getApple2OpsController().resetApple2WithMemoryVectorOverride();
  }

  function performApple2ResetSequence(options: any = {}) {
    return lazy.getApple2OpsController().performApple2ResetSequence(options);
  }

  async function loadApple2MemoryDumpBytes(bytes: any, offset: any, options = {}) {
    return lazy.getApple2OpsController().loadApple2MemoryDumpBytes(bytes, offset, options);
  }

  async function loadKaratekaDump() {
    return lazy.getApple2OpsController().loadKaratekaDump();
  }

  function selectedClock() {
    return lazy.getSimStatusController().selectedClock();
  }

  function maskForWidth(width: any) {
    return lazy.getSimStatusController().maskForWidth(width);
  }

  function refreshStatus() {
    lazy.getSimStatusController().refreshStatus();
    if (state?.terminal?.uartPassthrough) {
      const terminalController = lazy.getTerminalController();
      if (terminalController && typeof terminalController.syncUartPassthroughDisplay === 'function') {
        terminalController.syncUartPassthroughDisplay();
      }
    }
  }

  function drainTrace() {
    lazy.getSimRuntimeController().drainTrace();
  }

  function refreshWatchTable() {
    lazy.getWatchManager().refreshWatchTable();
  }

  function renderWatchList() {
    lazy.getWatchManager().renderWatchList();
  }

  function renderBreakpointList() {
    lazy.getWatchManager().renderBreakpointList();
  }

  function populateClockSelect() {
    lazy.getSimStatusController().populateClockSelect();
  }

  function initializeTrace(options: any = {}) {
    lazy.getSimRuntimeController().initializeTrace(options);
  }

  function addWatchSignal(name: any) {
    return lazy.getWatchManager().addWatchSignal(name);
  }

  function removeWatchSignal(name: any) {
    return lazy.getWatchManager().removeWatchSignal(name);
  }

  function checkBreakpoints() {
    return lazy.getWatchManager().checkBreakpoints();
  }

  function refreshApple2Screen() {
    lazy.getApple2VisualController().refreshApple2Screen();
  }

  function refreshApple2Debug() {
    lazy.getApple2VisualController().refreshApple2Debug();
  }

  function getApple2ProgramCounter() {
    return lazy.getApple2MemoryController().getApple2ProgramCounter();
  }

  function readApple2MappedMemory(start: any, length: any) {
    return lazy.getApple2MemoryController().readApple2MappedMemory(start, length);
  }

  function refreshMemoryView() {
    lazy.getApple2MemoryController().refreshMemoryView();
  }

  function queueApple2Key(value: any) {
    lazy.getSimLoopController().queueApple2Key(value);
  }

  function runApple2Cycles(cycles: any) {
    lazy.getSimLoopController().runApple2Cycles(cycles);
  }

  function stepSimulation() {
    lazy.getSimLoopController().stepSimulation();
  }

  function runFrame() {
    lazy.getSimLoopController().runFrame();
  }

  function resetThroughputSampling() {
    if (typeof lazy.getSimLoopController().resetThroughputSampling === 'function') {
      lazy.getSimLoopController().resetThroughputSampling();
    }
  }

  function setupP5() {
    setupWaveformP5({
      dom,
      state,
      runtime,
      waveformFontFamily,
      waveformPalette,
      formatValue,
      p5Ctor
    });
  }

  async function loadWasmInstance(backend = state.backend) {
    return lazy.getSimRuntimeController().loadWasmInstance(backend);
  }

  async function ensureBackendInstance(backend = state.backend) {
    return lazy.getSimRuntimeController().ensureBackendInstance(backend);
  }

  async function initializeSimulator(options: any = {}) {
    return lazy.getSimInitializerController().initializeSimulator(options);
  }

  async function loadSample(samplePathOverride = null) {
    return lazy.getRunnerActionsController().loadSample(samplePathOverride);
  }

  async function loadRunnerPreset(options: any = {}) {
    return lazy.getRunnerActionsController().loadRunnerPreset(options);
  }

  const shell = createShellDomainController({
    setActiveTab,
    setSidebarCollapsed,
    setTerminalOpen,
    applyTheme,
    terminalWriteLine,
    submitTerminalInput,
    terminalHistoryNavigate,
    terminalAppendInput,
    terminalBackspaceInput,
    terminalSetInput,
    terminalFocusInput,
    disposeDashboardLayoutBuilder,
    refreshDashboardRowSizing,
    refreshAllDashboardRowSizing,
    initializeDashboardLayoutBuilder
  });

  const runner = createRunnerDomainController({
    getRunnerPreset,
    currentRunnerPreset,
    loadRunnerPreset,
    loadSample,
    loadRunnerIrBundle,
    updateIrSourceVisibility,
    getRunnerActionsController: lazy.getRunnerActionsController,
    ensureBackendInstance
  });

  const components = createComponentDomainController({
    isComponentTabActive,
    refreshActiveComponentTab,
    refreshComponentExplorer,
    renderComponentTree,
    setComponentGraphFocus,
    currentComponentGraphFocusNode,
    renderComponentViews,
    zoomComponentGraphIn,
    zoomComponentGraphOut,
    resetComponentGraphViewport,
    clearComponentSourceOverride,
    resetComponentExplorerState
  });

  const apple2 = createApple2DomainController({
    isApple2UiEnabled,
    updateIoToggleUi,
    refreshApple2Screen,
    refreshApple2Debug,
    refreshMemoryView,
    setApple2SoundEnabled,
    updateApple2SpeakerAudio,
    queueApple2Key,
    performApple2ResetSequence,
    setMemoryDumpStatus,
    loadApple2DumpOrSnapshotFile,
    loadApple2DumpOrSnapshotAssetPath,
    saveApple2MemoryDump,
    saveApple2MemorySnapshot,
    loadLastSavedApple2Dump,
    loadKaratekaDump,
    resetApple2WithMemoryVectorOverride
  });

  const sim = createSimDomainController({
    setupP5,
    refreshStatus,
    initializeSimulator,
    initializeTrace,
    stepSimulation,
    runFrame,
    resetThroughputSampling,
    drainTrace,
    maskForWidth
  });

  const watch = createWatchDomainController({
    refreshWatchTable,
    addWatchSignal,
    removeWatchSignal,
    addBreakpointSignal,
    clearAllBreakpoints,
    removeBreakpointSignal,
    renderBreakpointList
  });

  return {
    shell,
    runner,
    components,
    apple2,
    sim,
    watch
  };
}
