import type { MergedDomRefs } from './dom';
import type {
  BreakpointModel,
  RunnerPresetModel,
  SelectOption,
  ThemeId
} from './models';
import type { BackendDef, RuntimeContext } from './runtime';
import type {
  AppState,
  ReduxAction,
  ReduxMutator,
  StoreDispatchers
} from './state';

export type UnknownFn = (...args: unknown[]) => unknown;
export type AsyncUnknownFn = (...args: unknown[]) => Promise<unknown>;
export type LogFn = (message: unknown) => void;

export interface ReduxStoreLike<TState = AppState> {
  dispatch(action: ReduxAction<unknown>): unknown;
  getState(): TState;
  subscribe(listener: () => void): () => void;
}

export interface ReduxLike {
  createStore<TState = AppState>(
    reducer: (state: TState | undefined, action: ReduxAction<unknown>) => TState,
    initialState: TState
  ): ReduxStoreLike<TState>;
}

export interface StoreActionsLike {
  setBackend(value: unknown): ReduxAction<unknown>;
  setTheme(value: unknown): ReduxAction<unknown>;
  setRunnerPreset(value: unknown): ReduxAction<unknown>;
  setActiveTab(value: unknown): ReduxAction<unknown>;
  setSidebarCollapsed(value: unknown): ReduxAction<unknown>;
  setTerminalOpen(value: unknown): ReduxAction<unknown>;
  setRunning(value: unknown): ReduxAction<unknown>;
  setCycle(value: unknown): ReduxAction<unknown>;
  setUiCyclesPending(value: unknown): ReduxAction<unknown>;
  setMemoryFollowPc(value: unknown): ReduxAction<unknown>;
  setMemoryShowSource(value: unknown): ReduxAction<unknown>;
  setApple2DisplayHires(value: unknown): ReduxAction<unknown>;
  setApple2DisplayColor(value: unknown): ReduxAction<unknown>;
  setApple2SoundEnabled(value: unknown): ReduxAction<unknown>;
  touch(meta?: unknown): ReduxAction<unknown>;
  mutate(mutator: ReduxMutator): ReduxAction<unknown>;
}

export interface ReduxSyncHelpers {
  syncReduxUxState(reason?: string): void;
  scheduleReduxUxSync(reason?: string): void;
}

export interface EventTargetLike {
  addEventListener(
    type: string,
    handler: EventListenerOrEventListenerObject,
    options?: boolean | AddEventListenerOptions
  ): void;
  removeEventListener(
    type: string,
    handler: EventListenerOrEventListenerObject,
    options?: boolean | EventListenerOptions
  ): void;
}

export interface ListenerGroup {
  on(
    target: EventTargetLike | null | undefined,
    type: string,
    handler: EventListenerOrEventListenerObject,
    options?: boolean | AddEventListenerOptions
  ): () => void;
  dispose(): void;
  size(): number;
}

export interface UiBindingRegistry {
  registerUiBinding(teardown: (() => void) | null | undefined): void;
  disposeUiBindings(): void;
}

export interface RunnerActionsController {
  preloadStartPreset(preset: RunnerPresetModel): Promise<unknown>;
  [key: string]: unknown;
}

export interface ShellTerminalDomainController {
  writeLine(message?: string): void;
  submitInput(): Promise<unknown>;
  historyNavigate(delta: number): unknown;
  appendInput(text?: string): unknown;
  backspaceInput(): unknown;
  setInput(text?: string): unknown;
  focusInput(): unknown;
}

export interface ShellDashboardDomainController {
  disposeLayoutBuilder(): void;
  refreshRowSizing(rootKey: string): void;
  refreshAllRowSizing(): void;
  initializeLayoutBuilder(): void;
}

export interface ShellDomainController {
  setActiveTab(tabId: string): void;
  setSidebarCollapsed(collapsed: boolean): void;
  setTerminalOpen(open: boolean, options?: { persist?: boolean; focus?: boolean }): void;
  applyTheme(theme: ThemeId | string, options?: { persist?: boolean }): void;
  terminal: ShellTerminalDomainController;
  dashboard: ShellDashboardDomainController;
}

export interface RunnerDomainController {
  getPreset(id: unknown): RunnerPresetModel;
  currentPreset(): RunnerPresetModel;
  loadPreset(options?: Record<string, unknown>): Promise<unknown>;
  loadSample(samplePathOverride?: string | null): Promise<unknown>;
  loadBundle(preset: RunnerPresetModel, options?: Record<string, unknown>): Promise<unknown>;
  updateIrSourceVisibility(): void;
  ensureBackendInstance(backend?: string): Promise<unknown>;
  getActionsController(): RunnerActionsController;
}

export interface ComponentDomainController {
  isTabActive(): boolean;
  refreshActiveTab(): void;
  refreshExplorer(): void;
  renderTree(): void;
  setGraphFocus(nodeId: string | null, showChildren?: boolean): void;
  currentGraphFocusNode(): unknown;
  renderViews(): void;
  zoomGraphIn(): unknown;
  zoomGraphOut(): unknown;
  resetGraphView(): unknown;
  clearSourceOverride(): void;
  resetExplorerState(): void;
}

export interface Apple2DomainController {
  isUiEnabled(): boolean;
  updateIoToggleUi(): void;
  refreshScreen(): void;
  refreshDebug(): void;
  refreshMemoryView(): void;
  setSoundEnabled(enabled: boolean): Promise<unknown>;
  updateSpeakerAudio(toggles: number, cyclesRun: number): void;
  queueKey(value: unknown): void;
  performResetSequence(options?: Record<string, unknown>): unknown;
  setMemoryDumpStatus(message: unknown): void;
  loadDumpOrSnapshotFile(file: File | Blob | unknown, offsetRaw: unknown): Promise<unknown>;
  loadDumpOrSnapshotAssetPath(assetPath: string, offsetRaw: unknown): Promise<unknown>;
  saveMemoryDump(): Promise<unknown>;
  saveMemorySnapshot(): Promise<unknown>;
  loadLastSavedDump(): Promise<unknown>;
  loadKaratekaDump(): Promise<unknown>;
  resetWithMemoryVectorOverride(): Promise<unknown>;
}

export interface SimDomainController {
  setupP5(): void;
  refreshStatus(): void;
  initializeSimulator(options?: Record<string, unknown>): Promise<unknown>;
  initializeTrace(options?: Record<string, unknown>): void;
  step(): void;
  runFrame(): void;
  resetThroughputSampling(): void;
  drainTrace(): void;
  maskForWidth(width: number): bigint;
}

export interface WatchDomainController {
  refreshTable(): void;
  addSignal(name: string): unknown;
  removeSignal(name: string): unknown;
  addBreakpoint(signal: string, valueRaw: unknown): unknown;
  clearBreakpoints(): void;
  removeBreakpoint(name: unknown): boolean;
  renderBreakpoints(): void;
}

export interface ControllerRegistry {
  shell: ShellDomainController;
  runner: RunnerDomainController;
  components: ComponentDomainController;
  apple2: Apple2DomainController;
  sim: SimDomainController;
  watch: WatchDomainController;
}

export interface ControllerRegistryOptions {
  dom: MergedDomRefs;
  state: AppState;
  runtime: RuntimeContext;
  appStore: ReduxStoreLike<AppState>;
  storeActions: StoreActionsLike;
  scheduleReduxUxSync: (reason?: string) => void;
  log: LogFn;
  setBackendState: (value: unknown) => void;
  setRunnerPresetState: (value: unknown) => void;
  setActiveTabState: (value: unknown) => void;
  setSidebarCollapsedState: (value: unknown) => void;
  setTerminalOpenState: (value: unknown) => void;
  setThemeState: (value: unknown) => void;
  setRunningState: (value: unknown) => void;
  setCycleState: (value: unknown) => void;
  setUiCyclesPendingState: (value: unknown) => void;
  setMemoryFollowPcState: (value: unknown) => void;
  setApple2DisplayHiresState: (value: unknown) => void;
  setApple2DisplayColorState: (value: unknown) => void;
  setApple2SoundEnabledState: (value: unknown) => void;
  replaceBreakpointsState: (value: unknown) => void;
  fetchImpl?: typeof fetch;
  webAssemblyApi?: typeof WebAssembly;
  requestFrame?: typeof requestAnimationFrame;
  windowRef?: Window;
  documentRef?: Document;
  localStorageRef?: Storage;
  eventCtor?: typeof Event;
  p5Ctor?: unknown;
}

export interface RegistryLazyGettersOptions extends ControllerRegistryOptions {
  setMemoryDumpStatus: (message: unknown) => void;
  setMemoryResetVectorInput: (value: unknown) => void;
  setActiveTab: (tabId: string) => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  setTerminalOpen: (open: boolean, options?: { persist?: boolean; focus?: boolean }) => void;
  applyTheme: (theme: ThemeId | string, options?: { persist?: boolean }) => void;
  updateIrSourceVisibility: () => void;
  loadRunnerPreset: (options?: Record<string, unknown>) => Promise<unknown>;
  loadRunnerIrBundle: (preset: RunnerPresetModel, options?: Record<string, unknown>) => Promise<unknown>;
  initializeSimulator: (options?: Record<string, unknown>) => Promise<unknown>;
  applyRunnerDefaults: (preset: RunnerPresetModel) => Promise<void>;
  clearComponentSourceOverride: () => void;
  resetComponentExplorerState: () => void;
  clearComponentSourceBundle: () => void;
  clearComponentSchematicBundle: () => void;
  setComponentSourceBundle: (bundle: unknown) => void;
  setComponentSchematicBundle: (bundle: unknown) => void;
  refreshComponentExplorer: () => void;
  isComponentTabActive: () => boolean;
  refreshActiveComponentTab: () => void;
  currentRunnerPreset: () => RunnerPresetModel;
  getRunnerPreset: (id: unknown) => RunnerPresetModel;
  currentComponentSourceText: () => string;
  destroyComponentGraph: () => void;
  refreshStatus: () => void;
  stepSimulation: () => void;
  addWatchSignal: (name: string) => unknown;
  removeWatchSignal: (name: string) => unknown;
  clearAllWatches: () => void;
  addBreakpointSignal: (signal: string, valueRaw: unknown) => unknown;
  clearAllBreakpoints: () => void;
  renderBreakpointList: () => void;
  refreshWatchTable: () => void;
  checkBreakpoints: () => boolean;
  selectedClock: (value?: string) => string;
  maskForWidth: (width: number) => bigint;
  populateClockSelect: () => void;
  initializeTrace: (options?: Record<string, unknown>) => void;
  renderWatchList: () => void;
  refreshApple2Screen: () => void;
  refreshApple2Debug: () => void;
  refreshMemoryView: () => void;
  updateApple2SpeakerAudio: (toggles: number, cyclesRun: number) => void;
  isApple2UiEnabled: () => boolean;
  updateIoToggleUi: () => void;
  apple2HiresLineAddress: (row: number) => number;
  getApple2ProgramCounter: () => number;
  ensureBackendInstance: (backend?: string) => Promise<unknown>;
  rebuildComponentExplorer: () => void;
  setComponentSourceOverride: (source?: string, meta?: unknown) => void;
  loadSample: (samplePathOverride?: string | null) => Promise<unknown>;
  resetApple2WithMemoryVectorOverride: () => Promise<unknown>;
  loadKaratekaDump: () => Promise<unknown>;
  loadLastSavedApple2Dump: () => Promise<unknown>;
  saveApple2MemoryDump: () => Promise<unknown>;
  saveApple2MemorySnapshot: () => Promise<unknown>;
  queueApple2Key: (value: unknown) => void;
  refreshAllDashboardRowSizing: () => void;
  drainTrace: () => void;
}

export interface StartupStoreBindings extends Partial<StoreDispatchers>, Partial<ReduxSyncHelpers> {
  setBackendState(value: unknown): void;
  setRunnerPresetState(value: unknown): void;
}

export interface StartupUtilityBindings {
  getBackendDef: (id: unknown) => BackendDef;
  parseNumeric: (text: unknown) => bigint | null;
  parseHexOrDec: (text: unknown, defaultValue?: number) => number;
  hexByte: (value: unknown) => string;
  normalizeTheme: (theme: unknown) => ThemeId;
  isSnapshotFileName: (name: unknown) => boolean;
}

export interface StartupKeys {
  SIDEBAR_COLLAPSED_KEY: string;
  TERMINAL_OPEN_KEY: string;
  THEME_KEY: string;
}

export interface StartupBindings {
  bindCoreBindings: unknown;
  bindMemoryBindings: unknown;
  bindComponentBindings: unknown;
  bindIoBindings: unknown;
  bindSimBindings: unknown;
  bindEditorBindings: unknown;
  bindCollapsiblePanels: unknown;
  COLLAPSIBLE_PANEL_SELECTOR: string;
  registerUiBinding: (teardown: (() => void) | null | undefined) => void;
  disposeUiBindings: () => void;
}

export interface StartupEnvironment {
  localStorageRef?: Storage;
  requestAnimationFrameImpl?: typeof requestAnimationFrame;
}

export interface StartupAppControllers extends Partial<ControllerRegistry> {
  shell?: ShellDomainController;
  runner?: RunnerDomainController;
  components?: ComponentDomainController;
  apple2?: Apple2DomainController;
  sim?: SimDomainController;
  watch?: WatchDomainController;
}

export interface StartupContext {
  dom: MergedDomRefs;
  state: AppState;
  runtime: RuntimeContext;
  appStore?: ReduxStoreLike<AppState>;
  storeActions?: StoreActionsLike;
  log: LogFn;
  env: StartupEnvironment;
  store: StartupStoreBindings;
  util: StartupUtilityBindings;
  keys: StartupKeys;
  bindings: StartupBindings;
  app: StartupAppControllers;
}

export interface StartupInitializationService {
  initialize(): Promise<void>;
  readSavedShellState(): {
    collapsed: boolean;
    terminalOpen: boolean;
    savedTheme: ThemeId;
  };
}

export interface StartupBindingRegistrationService {
  resetBindingLifecycle(): void;
  registerBindings(): void;
}

export interface StartupInitializationServiceDeps {
  dom: MergedDomRefs;
  state: AppState;
  store: StartupStoreBindings;
  util: StartupUtilityBindings;
  keys: StartupKeys;
  env: StartupEnvironment;
  shell: ShellDomainController;
  runner: RunnerDomainController;
  sim: SimDomainController;
  apple2: Apple2DomainController;
  terminal: ShellTerminalDomainController;
}

export interface StartupBindingRegistrationServiceDeps {
  dom: MergedDomRefs;
  state: AppState;
  runtime: RuntimeContext;
  bindings: StartupBindings;
  app: {
    shell: ShellDomainController;
    runner: RunnerDomainController;
    components: ComponentDomainController;
    apple2: Apple2DomainController;
    sim: SimDomainController;
    watch: WatchDomainController;
  };
  store: StartupStoreBindings & ReduxSyncHelpers;
  util: StartupUtilityBindings;
  env: StartupEnvironment;
  log: LogFn;
}

export interface InstallReduxGlobalsOptions {
  windowRef?: Window | (Window & Record<string, unknown>) | Record<string, unknown> | null;
  appStore?: ReduxStoreLike<AppState>;
  syncReduxUxState?: (reason?: string) => void;
  storeKey?: string;
  stateKey?: string;
  syncKey?: string;
}

export interface SetThemeOptions {
  persist?: boolean;
}

export interface SetTerminalOptions {
  persist?: boolean;
  focus?: boolean;
}

export interface SelectOptionsState {
  options: readonly SelectOption[];
  preferredValue?: string;
}
