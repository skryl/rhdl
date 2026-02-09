import { RUNNER_PRESETS } from '../../components/runner/config/presets.mjs';
import { formatValue } from '../lib/numeric_utils.mjs';
import { waveformFontFamily, waveformPalette } from '../lib/theme_utils.mjs';
import { setupWaveformP5 } from '../../components/watch/ui/waveform_panel.mjs';
import { createRegistryLazyGetters } from './registry_lazy_getters.mjs';
import { createShellDomainController } from '../../components/shell/controllers/domain.mjs';
import { createRunnerDomainController } from '../../components/runner/controllers/domain.mjs';
import { createComponentDomainController } from '../../components/explorer/controllers/domain.mjs';
import { createApple2DomainController } from '../../components/apple2/controllers/domain.mjs';
import { createSimDomainController } from '../../components/sim/controllers/domain.mjs';
import { createWatchDomainController } from '../../components/watch/controllers/domain.mjs';

export function createControllerRegistry(options = {}) {
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
    p5Ctor = globalThis.p5
  } = options;

  const lazy = createRegistryLazyGetters({
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

  function addBreakpointSignal(signal, valueRaw) {
    return lazy.getWatchManager().addBreakpointSignal(signal, valueRaw);
  }

  function clearAllBreakpoints() {
    lazy.getWatchManager().clearAllBreakpoints();
  }

  function removeBreakpointSignal(name) {
    const key = String(name || '').trim();
    if (!key) {
      return false;
    }
    const nextBreakpoints = state.breakpoints.filter((bp) => String(bp?.name || '') !== key);
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

  function terminalHistoryNavigate(delta) {
    return lazy.getTerminalController().historyNavigate(delta);
  }

  function getRunnerPreset(id) {
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

  function setComponentSourceBundle(bundle) {
    lazy.getComponentSourceController().setComponentSourceBundle(bundle);
  }

  function clearComponentSchematicBundle() {
    lazy.getComponentSourceController().clearComponentSchematicBundle();
  }

  function setComponentSchematicBundle(bundle) {
    lazy.getComponentSourceController().setComponentSchematicBundle(bundle);
  }

  async function loadRunnerIrBundle(preset, options = {}) {
    return lazy.getRunnerBundleLoader().loadRunnerIrBundle(preset, options);
  }

  function setActiveTab(tabId) {
    lazy.getShellStateController().setActiveTab(tabId);
  }

  function setSidebarCollapsed(collapsed) {
    lazy.getShellStateController().setSidebarCollapsed(collapsed);
  }

  function setTerminalOpen(open, { persist = true, focus = false } = {}) {
    lazy.getShellStateController().setTerminalOpen(open, { persist, focus });
  }

  function getDashboardLayoutManager() {
    return lazy.getDashboardLayoutController().getDashboardLayoutManager();
  }

  function disposeDashboardLayoutBuilder() {
    lazy.getDashboardLayoutController().disposeDashboardLayoutBuilder();
  }

  function refreshDashboardRowSizing(rootKey) {
    lazy.getDashboardLayoutController().refreshDashboardRowSizing(rootKey);
  }

  function refreshAllDashboardRowSizing() {
    lazy.getDashboardLayoutController().refreshAllDashboardRowSizing();
  }

  function initializeDashboardLayoutBuilder() {
    lazy.getDashboardLayoutController().initializeDashboardLayoutBuilder();
  }

  function applyTheme(theme, { persist = true } = {}) {
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

  function setComponentGraphFocus(nodeId, showChildren = true) {
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

  function apple2HiresLineAddress(row) {
    return lazy.getApple2OpsController().apple2HiresLineAddress(row);
  }

  async function setApple2SoundEnabled(enabled) {
    return lazy.getApple2OpsController().setApple2SoundEnabled(enabled);
  }

  function updateApple2SpeakerAudio(toggles, cyclesRun) {
    lazy.getApple2OpsController().updateApple2SpeakerAudio(toggles, cyclesRun);
  }

  function setMemoryDumpStatus(message) {
    lazy.getApple2OpsController().setMemoryDumpStatus(message);
  }

  function setMemoryResetVectorInput(value) {
    lazy.getApple2OpsController().setMemoryResetVectorInput(value);
  }

  async function saveApple2MemoryDump() {
    return lazy.getApple2OpsController().saveApple2MemoryDump();
  }

  async function saveApple2MemorySnapshot() {
    return lazy.getApple2OpsController().saveApple2MemorySnapshot();
  }

  async function loadApple2DumpOrSnapshotFile(file, offsetRaw) {
    return lazy.getApple2OpsController().loadApple2DumpOrSnapshotFile(file, offsetRaw);
  }

  async function loadLastSavedApple2Dump() {
    return lazy.getApple2OpsController().loadLastSavedApple2Dump();
  }

  async function resetApple2WithMemoryVectorOverride() {
    return lazy.getApple2OpsController().resetApple2WithMemoryVectorOverride();
  }

  function performApple2ResetSequence(options = {}) {
    return lazy.getApple2OpsController().performApple2ResetSequence(options);
  }

  async function loadApple2MemoryDumpBytes(bytes, offset, options = {}) {
    return lazy.getApple2OpsController().loadApple2MemoryDumpBytes(bytes, offset, options);
  }

  async function loadKaratekaDump() {
    return lazy.getApple2OpsController().loadKaratekaDump();
  }

  function selectedClock() {
    return lazy.getSimStatusController().selectedClock();
  }

  function maskForWidth(width) {
    return lazy.getSimStatusController().maskForWidth(width);
  }

  function refreshStatus() {
    lazy.getSimStatusController().refreshStatus();
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

  function initializeTrace() {
    lazy.getSimRuntimeController().initializeTrace();
  }

  function addWatchSignal(name) {
    return lazy.getWatchManager().addWatchSignal(name);
  }

  function removeWatchSignal(name) {
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

  function readApple2MappedMemory(start, length) {
    return lazy.getApple2MemoryController().readApple2MappedMemory(start, length);
  }

  function refreshMemoryView() {
    lazy.getApple2MemoryController().refreshMemoryView();
  }

  function queueApple2Key(value) {
    lazy.getSimLoopController().queueApple2Key(value);
  }

  function runApple2Cycles(cycles) {
    lazy.getSimLoopController().runApple2Cycles(cycles);
  }

  function stepSimulation() {
    lazy.getSimLoopController().stepSimulation();
  }

  function runFrame() {
    lazy.getSimLoopController().runFrame();
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

  async function initializeSimulator(options = {}) {
    return lazy.getSimInitializerController().initializeSimulator(options);
  }

  async function loadSample(samplePathOverride = null) {
    return lazy.getRunnerActionsController().loadSample(samplePathOverride);
  }

  async function loadRunnerPreset() {
    return lazy.getRunnerActionsController().loadRunnerPreset();
  }

  const shell = createShellDomainController({
    setActiveTab,
    setSidebarCollapsed,
    setTerminalOpen,
    applyTheme,
    terminalWriteLine,
    submitTerminalInput,
    terminalHistoryNavigate,
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
