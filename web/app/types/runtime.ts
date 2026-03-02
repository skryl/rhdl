import type { IrMetaModel } from './models';

export type BackendId = 'interpreter' | 'jit' | 'compiler';

export interface BackendDef {
  id: BackendId | string;
  label: string;
  wasmPath: string;
  corePrefix: string;
  allocPrefix: string;
  createFn: string;
  destroyFn: string;
  freeErrorFn: string;
}

export interface ThroughputMetrics {
  cyclesPerSecond: number;
  lastSampleTimeMs: number | null;
  lastSampleCycle: number;
}

export interface WasmExports {
  memory: WebAssembly.Memory;
  sim_create: (...args: number[]) => number;
  sim_destroy: (...args: number[]) => void;
  sim_exec: (...args: number[]) => number;
  sim_signal: (...args: number[]) => number;
  sim_trace: (...args: number[]) => number;
  sim_blob: (...args: number[]) => number;
  runner_mem?: (...args: number[]) => number;
  runner_probe?: (...args: number[]) => number;
  [key: string]: unknown;
}

export interface RuntimeContext {
  instance: WebAssembly.Instance | null;
  backendInstances: Map<string, WebAssembly.Instance>;
  sim: unknown;
  throughput: ThroughputMetrics;
  waveformP5: unknown;
  parser: unknown;
  irMeta: IrMetaModel | null;
  uiTeardowns: Array<() => void>;
}

export type RuntimeParserFactory = (() => unknown) | null;

export enum SimExecOp {
  EVALUATE = 0,
  TICK = 1,
  TICK_FORCED = 2,
  SET_PREV_CLOCK = 3,
  GET_CLOCK_LIST_IDX = 4,
  RESET = 5,
  RUN_TICKS = 6,
  SIGNAL_COUNT = 7,
  REG_COUNT = 8,
  COMPILE = 9,
  IS_COMPILED = 10
}

export enum SimSignalOp {
  HAS = 0,
  GET_INDEX = 1,
  PEEK = 2,
  POKE = 3,
  PEEK_INDEX = 4,
  POKE_INDEX = 5
}

export enum SimTraceOp {
  START = 0,
  START_STREAMING = 1,
  STOP = 2,
  ENABLED = 3,
  CAPTURE = 4,
  ADD_SIGNAL = 5,
  ADD_SIGNALS_MATCHING = 6,
  ALL_SIGNALS = 7,
  CLEAR_SIGNALS = 8,
  CLEAR = 9,
  CHANGE_COUNT = 10,
  SIGNAL_COUNT = 11,
  SET_TIMESCALE = 12,
  SET_MODULE_NAME = 13,
  SAVE_VCD = 14
}

export enum RunnerMemOp {
  LOAD = 0,
  READ = 1,
  WRITE = 2
}

export enum RunnerMemSpace {
  MAIN = 0,
  ROM = 1,
  BOOT_ROM = 2,
  VRAM = 3,
  ZPRAM = 4,
  WRAM = 5,
  FRAMEBUFFER = 6,
  DISK = 7,
  UART_TX = 8,
  UART_RX = 9
}

export enum RunnerProbe {
  KIND = 0,
  IS_MODE = 1,
  SPEAKER_TOGGLES = 2,
  FRAMEBUFFER_LEN = 3,
  FRAME_COUNT = 4,
  V_CNT = 5,
  H_CNT = 6,
  VBLANK_IRQ = 7,
  IF_R = 8,
  SIGNAL = 9,
  LCDC_ON = 10,
  H_DIV_CNT = 11,
  RISCV_UART_TX_LEN = 17
}
