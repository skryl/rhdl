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
import type { BreakpointModel, RunnerPresetModel, ThemeId } from '../../types/models';
import type { ControllerRegistry, ControllerRegistryOptions } from '../../types/services';

interface TerminalControllerLike {
  writeLine(message?: string): void;
  submitInput(): Promise<unknown>;
  historyNavigate(delta: number): unknown;
  appendInput(text?: string): unknown;
  backspaceInput(): unknown;
  setInput(text?: string): unknown;
  focusInput(): unknown;
  syncUartPassthroughDisplay?: () => void;
}

interface WatchManagerLike {
  clearAllWatches(): void;
  addBreakpointSignal(signal: string, valueRaw: unknown): unknown;
  clearAllBreakpoints(): void;
  refreshWatchTable(): void;
  renderWatchList(): void;
  renderBreakpointList(): void;
  addWatchSignal(name: string): unknown;
  removeWatchSignal(name: string): unknown;
  checkBreakpoints(): boolean;
}

interface ComponentSourceControllerLike {
  setComponentSourceOverride(source?: string, meta?: unknown): void;
  clearComponentSourceOverride(): void;
  resetComponentExplorerState(): void;
  currentComponentSourceText(): string;
  updateIrSourceVisibility(): void;
  clearComponentSourceBundle(): void;
  setComponentSourceBundle(bundle: unknown): void;
  clearComponentSchematicBundle(): void;
  setComponentSchematicBundle(bundle: unknown): void;
}

interface RunnerBundleLoaderLike {
  loadRunnerIrBundle(preset: RunnerPresetModel, options?: Record<string, unknown>): Promise<unknown>;
}

interface ShellStateControllerLike {
  setActiveTab(tabId: string): void;
  setSidebarCollapsed(collapsed: boolean): void;
  setTerminalOpen(open: boolean, options?: { persist?: boolean; focus?: boolean }): void;
  applyTheme(theme: ThemeId | string, options?: { persist?: boolean }): void;
}

interface DashboardLayoutControllerLike {
  getDashboardLayoutManager(): unknown;
  disposeDashboardLayoutBuilder(): void;
  refreshDashboardRowSizing(rootKey: string): void;
  refreshAllDashboardRowSizing(): void;
  initializeDashboardLayoutBuilder(): void;
}

interface ComponentExplorerControllerLike {
  ensureComponentSelection(): void;
  ensureComponentGraphFocus(): void;
  currentComponentGraphFocusNode(): { parentId: string | null } | null | void;
  setComponentGraphFocus(nodeId: string | null, showChildren?: boolean): void;
  renderComponentTree(): void;
  currentSelectedComponentNode(): unknown;
  isComponentTabActive(): boolean;
  renderComponentViews(): void;
  refreshActiveComponentTab(): void;
  destroyComponentGraph(): void;
  zoomComponentGraphIn(): boolean | void;
  zoomComponentGraphOut(): boolean | void;
  resetComponentGraphViewport(): boolean | void;
  rebuildComponentExplorer(meta: unknown, source: string): void;
  refreshComponentExplorer(): void;
}

interface Apple2OpsControllerLike {
  isApple2UiEnabled(): boolean;
  updateIoToggleUi(): void;
  apple2HiresLineAddress(row: number): number;
  setApple2SoundEnabled(enabled: boolean): Promise<unknown>;
  updateApple2SpeakerAudio(toggles: number, cyclesRun: number): void;
  setMemoryDumpStatus(message: unknown): void;
  setMemoryResetVectorInput(value: unknown): void;
  saveApple2MemoryDump(): Promise<unknown>;
  saveApple2MemorySnapshot(): Promise<unknown>;
  loadApple2DumpOrSnapshotFile(file: File | Blob | unknown, offsetRaw: unknown): Promise<unknown>;
  loadApple2DumpOrSnapshotAssetPath(assetPath: string, offsetRaw: unknown): Promise<unknown>;
  loadLastSavedApple2Dump(): Promise<unknown>;
  resetApple2WithMemoryVectorOverride(): Promise<unknown>;
  performApple2ResetSequence(options?: Record<string, unknown>): unknown;
  loadApple2MemoryDumpBytes(bytes: Uint8Array, offset: number, options?: Record<string, unknown>): Promise<unknown>;
  loadKaratekaDump(): Promise<unknown>;
}

interface Apple2VisualControllerLike {
  refreshApple2Screen(): void;
  refreshApple2Debug(): void;
}

interface Apple2MemoryControllerLike {
  getApple2ProgramCounter(): number;
  readApple2MappedMemory(start: number, length: number): unknown;
  refreshMemoryView(): void;
}

interface SimLoopControllerLike {
  queueApple2Key(value: unknown): void;
  runApple2Cycles(cycles: number): void;
  stepSimulation(): void;
  runFrame(): void;
  resetThroughputSampling?: () => void;
}

interface SimStatusControllerLike {
  selectedClock(value?: string): string;
  maskForWidth(width: number): bigint;
  refreshStatus(): void;
  populateClockSelect(): void;
}

interface SimRuntimeControllerLike {
  drainTrace(): void;
  initializeTrace(options?: Record<string, unknown>): void;
  loadWasmInstance(backend?: string): Promise<unknown>;
  ensureBackendInstance(backend?: string): Promise<unknown>;
}

interface SimInitializerControllerLike {
  initializeSimulator(options?: Record<string, unknown>): Promise<unknown>;
}

interface RunnerActionsControllerLike {
  loadSample(samplePathOverride?: string | null): Promise<unknown>;
  loadRunnerPreset(options?: Record<string, unknown>): Promise<unknown>;
}

interface RegistryLazyGettersLike {
  getTerminalController(): TerminalControllerLike;
  getWatchManager(): WatchManagerLike;
  getComponentSourceController(): ComponentSourceControllerLike;
  getRunnerBundleLoader(): RunnerBundleLoaderLike;
  getShellStateController(): ShellStateControllerLike;
  getDashboardLayoutController(): DashboardLayoutControllerLike;
  getComponentExplorerController(): ComponentExplorerControllerLike;
  getApple2OpsController(): Apple2OpsControllerLike;
  getApple2VisualController(): Apple2VisualControllerLike;
  getApple2MemoryController(): Apple2MemoryControllerLike;
  getSimLoopController(): SimLoopControllerLike;
  getSimStatusController(): SimStatusControllerLike;
  getSimRuntimeController(): SimRuntimeControllerLike;
  getSimInitializerController(): SimInitializerControllerLike;
  getRunnerActionsController(): RunnerActionsControllerLike;
}

function normalizePositiveInt(value: unknown, fallback: number | null = null) {
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function formatMemoryAddress(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return '';
  }
  const masked = Math.max(0, parsed);
  const width = masked > 0xFFFF ? 8 : 4;
  return `0x${Math.floor(masked).toString(16).toUpperCase().padStart(width, '0')}`;
}

export function createControllerRegistry(
  options: ControllerRegistryOptions = {} as ControllerRegistryOptions
): ControllerRegistry {
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
    p5Ctor = (globalThis as { p5?: unknown }).p5
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
  }) as RegistryLazyGettersLike;

  function terminalWriteLine(message = '') {
    lazy.getTerminalController().writeLine(message);
  }

  function clearAllWatches() {
    lazy.getWatchManager().clearAllWatches();
  }

  function addBreakpointSignal(signal: string, valueRaw: unknown) {
    return lazy.getWatchManager().addBreakpointSignal(signal, valueRaw);
  }

  function clearAllBreakpoints() {
    lazy.getWatchManager().clearAllBreakpoints();
  }

  function removeBreakpointSignal(name: unknown) {
    const key = String(name || '').trim();
    if (!key) {
      return false;
    }
    const nextBreakpoints = state.breakpoints.filter((bp: BreakpointModel) => String(bp?.name || '') !== key);
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

  function terminalHistoryNavigate(delta: number) {
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

  function getRunnerPreset(id: unknown): RunnerPresetModel {
    const key = String(id || '');
    if (key && RUNNER_PRESETS[key]) {
      return RUNNER_PRESETS[key] as RunnerPresetModel;
    }
    return RUNNER_PRESETS.generic as RunnerPresetModel;
  }

  function currentRunnerPreset() {
    return getRunnerPreset(state.runnerPreset);
  }

  function setComponentSourceOverride(source = '', meta: unknown = null) {
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

  function setComponentSourceBundle(bundle: unknown) {
    lazy.getComponentSourceController().setComponentSourceBundle(bundle);
  }

  function clearComponentSchematicBundle() {
    lazy.getComponentSourceController().clearComponentSchematicBundle();
  }

  function setComponentSchematicBundle(bundle: unknown) {
    lazy.getComponentSourceController().setComponentSchematicBundle(bundle);
  }

  async function loadRunnerIrBundle(preset: RunnerPresetModel, options: Record<string, unknown> = {}) {
    return lazy.getRunnerBundleLoader().loadRunnerIrBundle(preset, options);
  }

  async function applyRunnerDefaults(preset: RunnerPresetModel) {
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
      const dumpStart = Number.parseInt(String(ioConfig.memory.dumpStart), 10);
      if (Number.isFinite(dumpStart)) {
        dom.memoryStart.value = formatMemoryAddress(dumpStart);
      }
    }
    if (dom.memoryLength && ioConfig?.memory) {
      const dumpLength = Number.parseInt(String(ioConfig.memory.dumpLength), 10);
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

  function setActiveTab(tabId: string) {
    lazy.getShellStateController().setActiveTab(tabId);
  }

  function setSidebarCollapsed(collapsed: boolean) {
    lazy.getShellStateController().setSidebarCollapsed(collapsed);
  }

  function setTerminalOpen(open: boolean, { persist = true, focus = false }: { persist?: boolean; focus?: boolean } = {}) {
    lazy.getShellStateController().setTerminalOpen(open, { persist, focus });
  }

  function getDashboardLayoutManager() {
    return lazy.getDashboardLayoutController().getDashboardLayoutManager();
  }

  function disposeDashboardLayoutBuilder() {
    lazy.getDashboardLayoutController().disposeDashboardLayoutBuilder();
  }

  function refreshDashboardRowSizing(rootKey: string) {
    lazy.getDashboardLayoutController().refreshDashboardRowSizing(rootKey);
  }

  function refreshAllDashboardRowSizing() {
    lazy.getDashboardLayoutController().refreshAllDashboardRowSizing();
  }

  function initializeDashboardLayoutBuilder() {
    lazy.getDashboardLayoutController().initializeDashboardLayoutBuilder();
  }

  function applyTheme(theme: ThemeId | string, { persist = true }: { persist?: boolean } = {}) {
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

  function setComponentGraphFocus(nodeId: string | null, showChildren = true) {
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

  function apple2HiresLineAddress(row: number) {
    return lazy.getApple2OpsController().apple2HiresLineAddress(row);
  }

  async function setApple2SoundEnabled(enabled: boolean) {
    await lazy.getApple2OpsController().setApple2SoundEnabled(enabled);
  }

  function updateApple2SpeakerAudio(toggles: number, cyclesRun: number) {
    lazy.getApple2OpsController().updateApple2SpeakerAudio(toggles, cyclesRun);
  }

  function setMemoryDumpStatus(message: unknown) {
    lazy.getApple2OpsController().setMemoryDumpStatus(message);
  }

  function setMemoryResetVectorInput(value: unknown) {
    lazy.getApple2OpsController().setMemoryResetVectorInput(value);
  }

  async function saveApple2MemoryDump() {
    return !!(await lazy.getApple2OpsController().saveApple2MemoryDump());
  }

  async function saveApple2MemorySnapshot() {
    return !!(await lazy.getApple2OpsController().saveApple2MemorySnapshot());
  }

  async function loadApple2DumpOrSnapshotFile(file: File | Blob | unknown, offsetRaw: unknown) {
    return !!(await lazy.getApple2OpsController().loadApple2DumpOrSnapshotFile(file, offsetRaw));
  }

  async function loadApple2DumpOrSnapshotAssetPath(assetPath: string, offsetRaw: unknown) {
    return !!(await lazy.getApple2OpsController().loadApple2DumpOrSnapshotAssetPath(assetPath, offsetRaw));
  }

  async function loadLastSavedApple2Dump() {
    return !!(await lazy.getApple2OpsController().loadLastSavedApple2Dump());
  }

  async function resetApple2WithMemoryVectorOverride() {
    return !!(await lazy.getApple2OpsController().resetApple2WithMemoryVectorOverride());
  }

  function performApple2ResetSequence(options: Record<string, unknown> = {}) {
    return lazy.getApple2OpsController().performApple2ResetSequence(options);
  }

  async function loadApple2MemoryDumpBytes(bytes: Uint8Array, offset: number, options: Record<string, unknown> = {}) {
    return lazy.getApple2OpsController().loadApple2MemoryDumpBytes(bytes, offset, options);
  }

  async function loadKaratekaDump() {
    await lazy.getApple2OpsController().loadKaratekaDump();
  }

  function selectedClock() {
    return lazy.getSimStatusController().selectedClock();
  }

  function maskForWidth(width: number) {
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

  function initializeTrace(options: Record<string, unknown> = {}) {
    lazy.getSimRuntimeController().initializeTrace(options);
  }

  function addWatchSignal(name: string) {
    return lazy.getWatchManager().addWatchSignal(name);
  }

  function removeWatchSignal(name: string) {
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

  function readApple2MappedMemory(start: number, length: number) {
    return lazy.getApple2MemoryController().readApple2MappedMemory(start, length);
  }

  function refreshMemoryView() {
    lazy.getApple2MemoryController().refreshMemoryView();
  }

  function queueApple2Key(value: unknown) {
    lazy.getSimLoopController().queueApple2Key(value);
  }

  function runApple2Cycles(cycles: number) {
    lazy.getSimLoopController().runApple2Cycles(cycles);
  }

  function stepSimulation() {
    lazy.getSimLoopController().stepSimulation();
  }

  function runFrame() {
    lazy.getSimLoopController().runFrame();
  }

  function resetThroughputSampling() {
    const simLoopController = lazy.getSimLoopController();
    if (typeof simLoopController.resetThroughputSampling === 'function') {
      simLoopController.resetThroughputSampling();
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

  async function initializeSimulator(options: Record<string, unknown> = {}) {
    return lazy.getSimInitializerController().initializeSimulator(options);
  }

  async function loadSample(samplePathOverride: string | null = null) {
    return lazy.getRunnerActionsController().loadSample(samplePathOverride);
  }

  async function loadRunnerPreset(options: Record<string, unknown> = {}) {
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

  const apple2 = createApple2DomainController(({
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
  }) as unknown as Parameters<typeof createApple2DomainController>[0]) as ControllerRegistry['apple2'];

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
