export type DomElement = HTMLElement | null;

export type ValueDomElement = (HTMLElement & {
  value?: string;
}) | null;

export type CheckableDomElement = (HTMLElement & {
  checked?: boolean;
  value?: string;
}) | null;

export type FileDomElement = (HTMLElement & {
  files?: FileList | null;
  value?: string;
}) | null;

export interface ShellDomRefs {
  appShell: DomElement;
  viewer: Element | null;
  controlsPanel: DomElement;
  sidebarToggleBtn: DomElement;
  terminalToggleBtn: DomElement;
  terminalPanel: DomElement;
  terminalResizeHandle: DomElement;
  terminalOutput: ValueDomElement;
  terminalInput: ValueDomElement;
  terminalRunBtn: DomElement;
  editorTab: DomElement;
  editorVimWrap: DomElement;
  editorVimCanvas: DomElement;
  editorVimInput: ValueDomElement;
  editorFallback: ValueDomElement;
  editorExecuteBtn: DomElement;
  editorTerminalOutput: DomElement;
  editorTraceWrap: DomElement;
  editorStatus: DomElement;
  editorTraceMeta: DomElement;
  themeSelect: ValueDomElement;
  tabButtons: HTMLElement[];
  tabPanels: HTMLElement[];
}

export interface RunnerDomRefs {
  backendSelect: ValueDomElement;
  backendStatus: DomElement;
  runnerSelect: ValueDomElement;
  loadRunnerBtn: DomElement;
  runnerStatus: DomElement;
  irSourceSection: DomElement;
  irJson: ValueDomElement;
  irFileInput: FileDomElement;
  sampleSelect: ValueDomElement;
  loadSampleBtn: DomElement;
}

export interface SimDomRefs {
  initBtn: DomElement;
  resetBtn: DomElement;
  stepBtn: DomElement;
  runBtn: DomElement;
  pauseBtn: DomElement;
  stepTicks: ValueDomElement;
  runBatch: ValueDomElement;
  uiUpdateCycles: ValueDomElement;
  clockSignal: ValueDomElement;
  simStatus: DomElement;
  traceStatus: DomElement;
  traceStartBtn: DomElement;
  traceStopBtn: DomElement;
  traceClearBtn: DomElement;
  downloadVcdBtn: DomElement;
  canvasWrap: DomElement;
}

export interface WatchDomRefs {
  watchSignal: ValueDomElement;
  addWatchBtn: DomElement;
  watchList: DomElement;
  bpSignal: ValueDomElement;
  bpValue: ValueDomElement;
  addBpBtn: DomElement;
  clearBpBtn: DomElement;
  bpList: DomElement;
  watchTableBody: DomElement;
  eventLog: DomElement;
}

export interface Apple2DomRefs {
  apple2TextScreen: DomElement;
  apple2HiresCanvas: DomElement;
  apple2KeyInput: ValueDomElement;
  apple2SendKeyBtn: DomElement;
  apple2ClearKeysBtn: DomElement;
  apple2KeyStatus: DomElement;
  apple2DebugBody: DomElement;
  apple2SpeakerToggles: DomElement;
  toggleHires: CheckableDomElement;
  toggleColor: CheckableDomElement;
  toggleSound: CheckableDomElement;
  memoryDumpFile: FileDomElement;
  memoryDumpOffset: ValueDomElement;
  memoryDumpLoadBtn: DomElement;
  memoryDumpSaveBtn: DomElement;
  memorySnapshotSaveBtn: DomElement;
  memoryDumpLoadLastBtn: DomElement;
  memoryResetVector: ValueDomElement;
  memoryResetBtn: DomElement;
  loadKaratekaBtn: DomElement;
  memoryDumpStatus: DomElement;
}

export interface MemoryDomRefs {
  memoryStart: ValueDomElement;
  memoryLength: ValueDomElement;
  memoryFollowPc: CheckableDomElement;
  memoryShowSource: CheckableDomElement;
  memoryRefreshBtn: DomElement;
  memoryDump: DomElement;
  memoryDumpAssetTree: DomElement;
  memoryDumpAssetPath: ValueDomElement;
  memoryDisassembly: DomElement;
  memoryWriteAddr: ValueDomElement;
  memoryWriteValue: ValueDomElement;
  memoryWriteBtn: DomElement;
  memoryStatus: DomElement;
}

export interface ExplorerDomRefs {
  componentTree: DomElement;
  componentTitle: DomElement;
  componentMeta: DomElement;
  componentSignalMeta: DomElement;
  componentSignalBody: DomElement;
  componentGraphTitle: DomElement;
  componentGraphMeta: DomElement;
  componentGraphTopBtn: DomElement;
  componentGraphUpBtn: DomElement;
  componentGraphZoomInBtn: DomElement;
  componentGraphZoomOutBtn: DomElement;
  componentGraphResetViewBtn: DomElement;
  componentGraphFocusPath: DomElement;
  componentVisual: DomElement;
  componentLiveSignals: DomElement;
  componentConnectionMeta: DomElement;
  componentConnectionBody: DomElement;
  componentCode: DomElement;
}

export interface MergedDomRefs extends ShellDomRefs, RunnerDomRefs, SimDomRefs, WatchDomRefs, Apple2DomRefs, MemoryDomRefs, ExplorerDomRefs {}
