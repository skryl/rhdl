export type UnknownRecord = Record<string, unknown>;

export interface SelectOption {
  value: string;
  label: string;
}

export type ThemeId = 'shenzhen' | 'original';

export type ColorTriplet = [number, number, number];

export interface WaveformPalette {
  bg: ColorTriplet;
  axis: ColorTriplet;
  grid: ColorTriplet;
  label: ColorTriplet;
  trace: ColorTriplet;
  value: ColorTriplet;
  time: ColorTriplet;
  hint: ColorTriplet;
}

export interface RunnerIoMemoryModel {
  dumpStart: number;
  dumpLength: number;
  addressSpace: number;
  viewMapped: boolean;
  dumpReadMapped: boolean;
  directWriteMapped: boolean;
}

export interface RunnerIoDisplayTextModel {
  start: number;
  width: number;
  height: number;
  rowStride: number;
  rowLayout: string;
  charMask: number;
  asciiMin: number;
  asciiMax: number;
}

export interface RunnerIoDisplayModel {
  enabled: boolean;
  mode: string;
  text: RunnerIoDisplayTextModel;
}

export interface RunnerIoKeyboardModel {
  enabled: boolean;
  mode: string;
  dataAddr: number | null;
  strobeAddr: number | null;
  strobeValue: number;
  strobeClearValue: number | null;
  upperCase: boolean;
  setHighBit: boolean;
  enterCode: number;
  backspaceCode: number;
}

export interface RunnerIoSoundModel {
  enabled: boolean;
  mode: string;
  addr: number | null;
  mask: number;
}

export interface RunnerIoRomModel {
  path: string | null;
  offset: number;
  isRom: boolean;
}

export interface RunnerIoConfigModel {
  enabled: boolean;
  api: string;
  memory: RunnerIoMemoryModel;
  display: RunnerIoDisplayModel;
  keyboard: RunnerIoKeyboardModel;
  sound: RunnerIoSoundModel;
  rom: RunnerIoRomModel;
  pcSignalCandidates: string[];
  watchSignals: string[];
}

export interface RunnerPresetDefaultsModel {
  displayHires?: boolean;
  displayColor?: boolean;
  memoryFollowPc?: boolean;
  stepTicks?: number;
  runBatch?: number;
  uiUpdateCycles?: number;
  loadKaratekaDumpOnLoad?: boolean;
  [key: string]: unknown;
}

export interface RunnerPresetModel {
  id: string;
  label?: string;
  sampleLabel?: string;
  samplePath?: string;
  simIrPath?: string;
  preferredTab?: string;
  autoLoadOnBoot?: boolean;
  usesManualIr?: boolean;
  enableApple2Ui?: boolean;
  romPath?: string;
  defaults?: RunnerPresetDefaultsModel;
  io?: Partial<RunnerIoConfigModel>;
  [key: string]: unknown;
}

export interface BreakpointModel extends UnknownRecord {
  name?: string;
  value?: unknown;
  width?: number;
}

export interface WatchEntryModel extends UnknownRecord {
  name?: string;
  width?: number;
}

export interface WatchRowModel extends UnknownRecord {
  name?: string;
  width?: number;
  value?: unknown;
}

export interface ExplorerComponentsModel {
  model: unknown;
  selectedNodeId: string | null;
  parseError: string;
  sourceKey: string;
  overrideSource: string;
  overrideMeta: UnknownRecord | null;
  graph: unknown;
  graphKey: string;
  graphSelectedId: string | null;
  graphFocusId: string | null;
  graphShowChildren: boolean;
  graphLastTap: unknown;
  graphHighlightedSignal: string | null;
  graphLiveValues: Map<string, unknown>;
  graphLayoutEngine: string;
  graphElkAvailable: boolean;
  sourceBundle: unknown;
  sourceBundleByClass: Map<string, string>;
  sourceBundleByModule: Map<string, string>;
  schematicBundle: unknown;
  schematicBundleByPath: Map<string, string>;
  [key: string]: unknown;
}

export interface IrEntryModel extends UnknownRecord {
  name: string;
  width?: number | string;
  direction?: string | null;
}

export interface IrProcessModel extends UnknownRecord {
  clocked?: boolean;
  clock?: string;
}

export interface IrModel extends UnknownRecord {
  ports?: IrEntryModel[];
  nets?: IrEntryModel[];
  regs?: IrEntryModel[];
  processes?: IrProcessModel[];
}

export interface IrSignalInfoModel {
  name: string;
  width: number;
  kind: string;
  direction: string | null;
  entry: IrEntryModel;
}

export interface IrMetaModel {
  ir: IrModel;
  widths: Map<string, number>;
  signalInfo: Map<string, IrSignalInfoModel>;
  names: string[];
  clocks: string[];
  clockCandidates: string[];
}
