import type {
  BreakpointModel,
  ExplorerComponentsModel,
  ThemeId,
  WatchEntryModel,
  WatchRowModel
} from './models';
import type { BackendId } from './runtime';

export type AppActionType =
  | 'app/setBackend'
  | 'sim/setRunning'
  | 'sim/setCycle'
  | 'sim/setUiCyclesPending'
  | 'app/setTheme'
  | 'app/setActiveTab'
  | 'app/setSidebarCollapsed'
  | 'app/setTerminalOpen'
  | 'app/setRunnerPreset'
  | 'memory/setFollowPc'
  | 'memory/setShowSource'
  | 'apple2/setDisplayHires'
  | 'apple2/setDisplayColor'
  | 'apple2/setSoundEnabled'
  | 'watch/set'
  | 'watch/remove'
  | 'watch/clear'
  | 'breakpoint/addOrReplace'
  | 'breakpoint/remove'
  | 'breakpoint/clear'
  | 'app/touch'
  | 'state/mutate';

export interface ReduxAction<TPayload = unknown, TType extends string = AppActionType | string> {
  type?: TType;
  payload?: TPayload;
  meta?: unknown;
  [key: string]: unknown;
}

export interface ShellDashboardResizingState {
  active: boolean;
  rootKey: string;
  rowSignature: string;
  startY: number;
  startHeight: number;
}

export interface ShellDashboardState {
  rootElements: Map<string, HTMLElement>;
  layouts: Record<string, unknown>;
  draggingItemId: string;
  draggingRootKey: string;
  dropTargetItemId: string;
  dropPosition: string;
  resizeBound: boolean;
  resizeTeardown: (() => void) | null;
  panelTeardowns: Map<string, () => void>;
  resizing: ShellDashboardResizingState;
  [key: string]: unknown;
}

export interface SimState {
  backend: BackendId | string;
  running: boolean;
  cycle: number;
  uiCyclesPending: number;
  [key: string]: unknown;
}

export interface ShellState {
  theme: ThemeId | string;
  sidebarCollapsed: boolean;
  terminalOpen: boolean;
  activeTab: string;
  dashboard: ShellDashboardState;
  [key: string]: unknown;
}

export interface RunnerState {
  runnerPreset: string;
  [key: string]: unknown;
}

export interface MemorySliceState {
  followPc: boolean;
  showSource: boolean;
  disasmLines: number;
  lastSavedDump: unknown;
  [key: string]: unknown;
}

export interface MemoryState {
  memory: MemorySliceState;
  [key: string]: unknown;
}

export interface Apple2SliceState {
  enabled: boolean;
  keyQueue: unknown[];
  lastSpeakerToggles: number;
  lastCpuResult: unknown;
  lastMappedSoundValue: unknown;
  baseRomBytes: Uint8Array | null;
  ioConfig: unknown;
  displayHires: boolean;
  displayColor: boolean;
  soundEnabled: boolean;
  audioCtx: AudioContext | null;
  audioOsc: OscillatorNode | null;
  audioGain: GainNode | null;
  [key: string]: unknown;
}

export interface Apple2State {
  apple2: Apple2SliceState;
  [key: string]: unknown;
}

export interface WatchState {
  watches: Map<string, WatchEntryModel>;
  watchRows: WatchRowModel[];
  breakpoints: BreakpointModel[];
  [key: string]: unknown;
}

export interface TerminalSliceState {
  history: string[];
  historyIndex: number;
  busy: boolean;
  lines: string[];
  inputBuffer: string;
  uartPassthrough: boolean;
  [key: string]: unknown;
}

export interface TerminalState {
  terminal: TerminalSliceState;
  [key: string]: unknown;
}

export interface ComponentsState {
  components: ExplorerComponentsModel;
  [key: string]: unknown;
}

export interface AppState extends SimState, ShellState, RunnerState, MemoryState, Apple2State, WatchState, TerminalState, ComponentsState {
  __lastReduxMeta?: unknown;
  [key: string]: unknown;
}

export type ReduxMutator = (state: AppState) => void;

export interface StoreDispatchers {
  setBackendState(value: unknown): void;
  setThemeState(value: unknown): void;
  setRunnerPresetState(value: unknown): void;
  setActiveTabState(value: unknown): void;
  setSidebarCollapsedState(value: unknown): void;
  setTerminalOpenState(value: unknown): void;
  setRunningState(value: unknown): void;
  setCycleState(value: unknown): void;
  setUiCyclesPendingState(value: unknown): void;
  setMemoryFollowPcState(value: unknown): void;
  setMemoryShowSourceState(value: unknown): void;
  setApple2DisplayHiresState(value: unknown): void;
  setApple2DisplayColorState(value: unknown): void;
  setApple2SoundEnabledState(value: unknown): void;
  replaceBreakpointsState(nextBreakpoints: unknown): void;
}
