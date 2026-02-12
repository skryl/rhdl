import { getBackendDef } from './backend_defs.mjs';

const SIM_CAP_SIGNAL_INDEX = 1 << 0;
const SIM_CAP_FORCED_CLOCK = 1 << 1;
const SIM_CAP_TRACE = 1 << 2;
const SIM_CAP_TRACE_STREAMING = 1 << 3;
const SIM_CAP_RUNNER_INTERP_JIT = 1 << 4;
const SIM_CAP_COMPILE_COMPILER = 1 << 4;
const SIM_CAP_GENERATED_CODE_COMPILER = 1 << 5;
const SIM_CAP_RUNNER_COMPILER = 1 << 6;

const SIM_SIGNAL_HAS = 0;
const SIM_SIGNAL_GET_INDEX = 1;
const SIM_SIGNAL_PEEK = 2;
const SIM_SIGNAL_POKE = 3;
const SIM_SIGNAL_PEEK_INDEX = 4;
const SIM_SIGNAL_POKE_INDEX = 5;

const SIM_EXEC_EVALUATE = 0;
const SIM_EXEC_TICK = 1;
const SIM_EXEC_TICK_FORCED = 2;
const SIM_EXEC_SET_PREV_CLOCK = 3;
const SIM_EXEC_GET_CLOCK_LIST_IDX = 4;
const SIM_EXEC_RESET = 5;
const SIM_EXEC_RUN_TICKS = 6;
const SIM_EXEC_SIGNAL_COUNT = 7;
const SIM_EXEC_REG_COUNT = 8;
const SIM_EXEC_COMPILE = 9;
const SIM_EXEC_IS_COMPILED = 10;

const SIM_TRACE_START = 0;
const SIM_TRACE_START_STREAMING = 1;
const SIM_TRACE_STOP = 2;
const SIM_TRACE_ENABLED = 3;
const SIM_TRACE_CAPTURE = 4;
const SIM_TRACE_ADD_SIGNAL = 5;
const SIM_TRACE_ADD_SIGNALS_MATCHING = 6;
const SIM_TRACE_ALL_SIGNALS = 7;
const SIM_TRACE_CLEAR_SIGNALS = 8;
const SIM_TRACE_CLEAR = 9;
const SIM_TRACE_CHANGE_COUNT = 10;
const SIM_TRACE_SIGNAL_COUNT = 11;
const SIM_TRACE_SET_TIMESCALE = 12;
const SIM_TRACE_SET_MODULE_NAME = 13;
const SIM_TRACE_SAVE_VCD = 14;

const SIM_BLOB_INPUT_NAMES = 0;
const SIM_BLOB_OUTPUT_NAMES = 1;
const SIM_BLOB_TRACE_TO_VCD = 2;
const SIM_BLOB_TRACE_TAKE_LIVE_VCD = 3;
const SIM_BLOB_GENERATED_CODE = 4;

const RUNNER_KIND_APPLE2 = 1;
const RUNNER_KIND_MOS6502 = 2;
const RUNNER_KIND_GAMEBOY = 3;
const RUNNER_KIND_CPU8BIT = 4;

const RUNNER_MEM_OP_LOAD = 0;
const RUNNER_MEM_OP_READ = 1;
const RUNNER_MEM_OP_WRITE = 2;

const RUNNER_MEM_SPACE_MAIN = 0;
const RUNNER_MEM_SPACE_ROM = 1;
const RUNNER_MEM_SPACE_BOOT_ROM = 2;
const RUNNER_MEM_SPACE_VRAM = 3;
const RUNNER_MEM_SPACE_ZPRAM = 4;
const RUNNER_MEM_SPACE_WRAM = 5;
const RUNNER_MEM_SPACE_FRAMEBUFFER = 6;

const RUNNER_MEM_FLAG_MAPPED = 1;

const RUNNER_RUN_MODE_BASIC = 0;
const RUNNER_RUN_MODE_FULL = 1;

const RUNNER_CONTROL_SET_RESET_VECTOR = 0;
const RUNNER_CONTROL_RESET_SPEAKER_TOGGLES = 1;
const RUNNER_CONTROL_RESET_LCD = 2;

const RUNNER_PROBE_KIND = 0;
const RUNNER_PROBE_IS_MODE = 1;
const RUNNER_PROBE_SPEAKER_TOGGLES = 2;
const RUNNER_PROBE_FRAMEBUFFER_LEN = 3;
const RUNNER_PROBE_FRAME_COUNT = 4;
const RUNNER_PROBE_V_CNT = 5;
const RUNNER_PROBE_H_CNT = 6;
const RUNNER_PROBE_VBLANK_IRQ = 7;
const RUNNER_PROBE_IF_R = 8;
const RUNNER_PROBE_SIGNAL = 9;
const RUNNER_PROBE_LCDC_ON = 10;
const RUNNER_PROBE_H_DIV_CNT = 11;

export class WasmIrSimulator {
  constructor(instance, irJson, backend = 'interpreter', subCycles = 14) {
    this.instance = instance;
    this.backend = getBackendDef(backend);
    this.e = WasmIrSimulator.normalizeExports(instance.exports, this.backend);
    this.features = {};
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();
    this.ctx = 0;
    this.clockCache = new Map();
    this.traceSnapshot = '';
    this.simRunnerSpeakerToggles = 0;

    this.requireExport('memory');
    this.requireExport('sim_create');
    this.requireExport('sim_destroy');
    this.requireExport('sim_wasm_alloc');
    this.requireExport('sim_wasm_dealloc');
    this.requireExport('sim_get_caps');
    this.requireExport('sim_signal');
    this.requireExport('sim_exec');
    this.requireExport('sim_trace');
    this.requireExport('sim_blob');

    const jsonBytes = this.encoder.encode(irJson);
    const jsonPtr = this.alloc(jsonBytes.length);
    const errOutPtr = this.alloc(4);

    try {
      this.u8().set(jsonBytes, jsonPtr);
      this.u32().set([0], errOutPtr >>> 2);

      this.ctx = this.e.sim_create(jsonPtr, jsonBytes.length, subCycles, errOutPtr);
      if (this.ctx === 0) {
        const errPtr = this.u32()[errOutPtr >>> 2];
        if (errPtr) {
          const msg = this.readCString(errPtr);
          this.e.sim_free_error(errPtr);
          throw new Error(msg || 'sim_create failed');
        }
        throw new Error('sim_create failed');
      }

      this.features = this.readCoreFeatures();

      if (this.features.requiresCompile) {
        const compileErrOut = this.alloc(4);
        try {
          this.u32().set([0], compileErrOut >>> 2);
          const ok = this.e.sim_exec(this.ctx, SIM_EXEC_COMPILE, 0, 0, 0, compileErrOut);
          if (ok === 0) {
            const errPtr = this.u32()[compileErrOut >>> 2];
            if (errPtr) {
              const msg = this.readCString(errPtr);
              this.e.sim_free_error(errPtr);
              throw new Error(msg || 'sim_compile failed');
            }
            throw new Error('sim_compile failed');
          }
        } finally {
          this.dealloc(compileErrOut, 4);
        }
      }
    } finally {
      this.dealloc(jsonPtr, jsonBytes.length);
      this.dealloc(errOutPtr, 4);
    }
  }

  static normalizeExports(raw, backendDef) {
    const pick = (...names) => {
      for (const name of names) {
        if (name && typeof raw[name] === 'function') {
          return raw[name].bind(raw);
        }
      }
      return null;
    };
    const must = (...names) => {
      const fn = pick(...names);
      if (!fn) {
        throw new Error(`Missing WASM export (backend ${backendDef.id}): ${names[0]}`);
      }
      return fn;
    };

    const core = backendDef.corePrefix;
    const alloc = backendDef.allocPrefix || core;

    const out = {
      memory: raw.memory
    };

    out.sim_create = must(backendDef.createFn, 'sim_create');
    out.sim_destroy = must(backendDef.destroyFn, 'sim_destroy');
    out.sim_free_error = must(backendDef.freeErrorFn, 'sim_free_error');
    out.sim_wasm_alloc = must(`${alloc}_wasm_alloc`, 'sim_wasm_alloc');
    out.sim_wasm_dealloc = must(`${alloc}_wasm_dealloc`, 'sim_wasm_dealloc');

    out.sim_get_caps = must('sim_get_caps');
    out.sim_signal = must('sim_signal');
    out.sim_exec = must('sim_exec');
    out.sim_trace = must('sim_trace');
    out.sim_blob = must('sim_blob');

    out.runner_get_caps = pick('runner_get_caps');
    out.runner_mem = pick('runner_mem');
    out.runner_run = pick('runner_run');
    out.runner_control = pick('runner_control');
    out.runner_probe = pick('runner_probe');

    out.__features = {
      hasRunnerApi: !!(
        out.runner_get_caps
        && out.runner_mem
        && out.runner_run
        && out.runner_control
        && out.runner_probe
      )
    };

    return out;
  }

  requireExport(name) {
    if (!this.e[name]) {
      throw new Error(`Missing WASM export: ${name}`);
    }
  }

  hasExport(name) {
    return typeof this.e[name] === 'function';
  }

  memoryBuffer() {
    return this.e.memory.buffer;
  }

  u8() {
    return new Uint8Array(this.memoryBuffer());
  }

  u32() {
    return new Uint32Array(this.memoryBuffer());
  }

  alloc(size) {
    return this.e.sim_wasm_alloc(Math.max(1, size));
  }

  dealloc(ptr, size) {
    if (ptr) {
      this.e.sim_wasm_dealloc(ptr, Math.max(1, size));
    }
  }

  withCString(text, fn) {
    const bytes = this.encoder.encode(String(text));
    const ptr = this.alloc(bytes.length + 1);
    try {
      const mem = this.u8();
      mem.set(bytes, ptr);
      mem[ptr + bytes.length] = 0;
      return fn(ptr);
    } finally {
      this.dealloc(ptr, bytes.length + 1);
    }
  }

  readCString(ptr) {
    if (!ptr) {
      return '';
    }

    const mem = this.u8();
    let end = ptr;
    while (end < mem.length && mem[end] !== 0) {
      end += 1;
    }
    return this.decoder.decode(mem.subarray(ptr, end));
  }

  takeOwnedCString(ptr, freeFn = null) {
    if (!ptr) {
      return '';
    }

    const text = this.readCString(ptr);
    if (this.e[freeFn]) {
      this.e[freeFn](ptr);
    }
    return text;
  }

  readCoreFeatures() {
    const capsPtr = this.alloc(4);
    try {
      this.u8().fill(0, capsPtr, capsPtr + 4);
      const ok = this.e.sim_get_caps(this.ctx, capsPtr);
      const flags = ok !== 0 ? new DataView(this.memoryBuffer(), capsPtr, 4).getUint32(0, true) : 0;
      const isCompilerBackend = this.backend?.id === 'compiler';
      const hasRunnerCap = isCompilerBackend
        ? (flags & SIM_CAP_RUNNER_COMPILER) !== 0
        : (flags & SIM_CAP_RUNNER_INTERP_JIT) !== 0;
      return {
        hasSignalIndex: (flags & SIM_CAP_SIGNAL_INDEX) !== 0,
        hasForcedClock: (flags & SIM_CAP_FORCED_CLOCK) !== 0,
        hasLiveTrace: (flags & SIM_CAP_TRACE) !== 0,
        requiresCompile: isCompilerBackend && (flags & SIM_CAP_COMPILE_COMPILER) !== 0,
        hasGeneratedCode: isCompilerBackend && (flags & SIM_CAP_GENERATED_CODE_COMPILER) !== 0,
        hasRunnerApi: hasRunnerCap || this.e.__features?.hasRunnerApi === true
      };
    } finally {
      this.dealloc(capsPtr, 4);
    }
  }

  simSignal(op, { name = null, idx = 0, value = 0 } = {}) {
    const invoke = (namePtr) => {
      const outPtr = this.alloc(8);
      try {
        this.u8().fill(0, outPtr, outPtr + 8);
        const ok = this.e.sim_signal(
          this.ctx,
          Number(op) >>> 0,
          namePtr || 0,
          Number(idx) >>> 0,
          Number(value) >>> 0,
          outPtr
        );
        const outValue = new DataView(this.memoryBuffer(), outPtr, 8).getUint32(0, true);
        return { ok: ok !== 0, value: outValue };
      } finally {
        this.dealloc(outPtr, 8);
      }
    };

    if (typeof name === 'string') {
      return this.withCString(name, (ptr) => invoke(ptr));
    }
    return invoke(0);
  }

  simExec(op, arg0 = 0, arg1 = 0, errorOutPtr = 0) {
    const outPtr = this.alloc(8);
    try {
      this.u8().fill(0, outPtr, outPtr + 8);
      const ok = this.e.sim_exec(
        this.ctx,
        Number(op) >>> 0,
        Number(arg0) >>> 0,
        Number(arg1) >>> 0,
        outPtr,
        errorOutPtr || 0
      );
      const outValue = new DataView(this.memoryBuffer(), outPtr, 8).getUint32(0, true);
      return { ok: ok !== 0, value: outValue };
    } finally {
      this.dealloc(outPtr, 8);
    }
  }

  simTrace(op, strArg = null) {
    const invoke = (argPtr) => {
      const outPtr = this.alloc(8);
      try {
        this.u8().fill(0, outPtr, outPtr + 8);
        const ok = this.e.sim_trace(
          this.ctx,
          Number(op) >>> 0,
          argPtr || 0,
          outPtr
        );
        const outValue = new DataView(this.memoryBuffer(), outPtr, 8).getUint32(0, true);
        return { ok: ok !== 0, value: outValue };
      } finally {
        this.dealloc(outPtr, 8);
      }
    };

    if (typeof strArg === 'string') {
      return this.withCString(strArg, (ptr) => invoke(ptr));
    }
    return invoke(0);
  }

  simBlob(op) {
    const required = this.e.sim_blob(this.ctx, Number(op) >>> 0, 0, 0) >>> 0;
    if (required === 0) {
      return '';
    }
    const ptr = this.alloc(required);
    try {
      const actual = this.e.sim_blob(this.ctx, Number(op) >>> 0, ptr, required) >>> 0;
      if (actual === 0) {
        return '';
      }
      return this.decoder.decode(new Uint8Array(this.memoryBuffer().slice(ptr, ptr + actual)));
    } finally {
      this.dealloc(ptr, required);
    }
  }

  destroy() {
    if (this.ctx) {
      this.e.sim_destroy(this.ctx);
      this.ctx = 0;
    }
  }

  signal_count() {
    return this.simExec(SIM_EXEC_SIGNAL_COUNT).value >>> 0;
  }

  reg_count() {
    return this.simExec(SIM_EXEC_REG_COUNT).value >>> 0;
  }

  input_names() {
    const csv = this.simBlob(SIM_BLOB_INPUT_NAMES);
    if (!csv) {
      return [];
    }
    return csv.split(',').filter(Boolean);
  }

  output_names() {
    const csv = this.simBlob(SIM_BLOB_OUTPUT_NAMES);
    if (!csv) {
      return [];
    }
    return csv.split(',').filter(Boolean);
  }

  get_signal_idx(name) {
    const result = this.simSignal(SIM_SIGNAL_GET_INDEX, { name });
    return result.ok ? (result.value | 0) : -1;
  }

  has_signal(name) {
    return this.simSignal(SIM_SIGNAL_HAS, { name }).value !== 0;
  }

  poke(name, value) {
    return this.simSignal(SIM_SIGNAL_POKE, { name, value }).ok;
  }

  peek(name) {
    return this.simSignal(SIM_SIGNAL_PEEK, { name }).value;
  }

  poke_by_idx(idx, value) {
    this.simSignal(SIM_SIGNAL_POKE_INDEX, { idx, value });
  }

  peek_by_idx(idx) {
    return this.simSignal(SIM_SIGNAL_PEEK_INDEX, { idx }).value;
  }

  tick_forced() {
    this.simExec(SIM_EXEC_TICK_FORCED);
    this.captureTraceIfEnabled();
  }

  set_prev_clock(clockListIdx, value) {
    this.simExec(SIM_EXEC_SET_PREV_CLOCK, clockListIdx, value);
  }

  get_clock_list_idx(signalIdx) {
    const result = this.simExec(SIM_EXEC_GET_CLOCK_LIST_IDX, signalIdx, 0);
    return result.ok ? (result.value | 0) : -1;
  }

  trace_enabled() {
    return this.simTrace(SIM_TRACE_ENABLED).value !== 0;
  }

  trace_capture() {
    this.simTrace(SIM_TRACE_CAPTURE);
  }

  captureTraceIfEnabled() {
    if (this.trace_enabled()) {
      this.trace_capture();
    }
  }

  evaluate() {
    this.simExec(SIM_EXEC_EVALUATE);
    this.captureTraceIfEnabled();
  }

  tick() {
    this.simExec(SIM_EXEC_TICK);
    this.captureTraceIfEnabled();
  }

  run_ticks(n) {
    const ticks = Math.max(0, Number.parseInt(n, 10) || 0);
    for (let i = 0; i < ticks; i += 1) {
      this.tick();
    }
  }

  run_clock_ticks(clockSignal, cycles) {
    if (!this.features.hasSignalIndex) {
      this.run_ticks(cycles);
      return;
    }

    const cached = this.clockCache.get(clockSignal);
    let clockIdx;
    let clockListIdx;
    let mode;

    if (cached) {
      ({ clockIdx, clockListIdx, mode } = cached);
    } else {
      clockIdx = this.get_signal_idx(clockSignal);
      if (clockIdx < 0) {
        throw new Error(`Unknown clock signal: ${clockSignal}`);
      }
      clockListIdx = this.get_clock_list_idx(clockIdx);
      mode = clockListIdx >= 0 ? 'forced' : 'driven';
      this.clockCache.set(clockSignal, { clockIdx, clockListIdx, mode });
    }

    const n = Math.max(0, Number.parseInt(cycles, 10) || 0);

    if (mode === 'forced') {
      const traceOn = this.trace_enabled();
      for (let i = 0; i < n; i += 1) {
        this.set_prev_clock(clockListIdx, 0);
        this.poke_by_idx(clockIdx, 1);
        this.simExec(SIM_EXEC_TICK_FORCED);
        if (traceOn) {
          this.trace_capture();
        }

        this.poke_by_idx(clockIdx, 0);
        this.simExec(SIM_EXEC_EVALUATE);
        if (traceOn) {
          this.trace_capture();
        }
      }
      return;
    }

    // Driven mode: toggle an external/root clock and let evaluate()+tick()
    // propagate edges to all derived internal clock domains.
    for (let i = 0; i < n; i += 1) {
      this.poke_by_idx(clockIdx, 0);
      this.evaluate();
      this.poke_by_idx(clockIdx, 1);
      this.tick();
      this.poke_by_idx(clockIdx, 0);
      this.evaluate();
    }
  }

  clock_mode(name) {
    if (!name) {
      return 'none';
    }
    if (!this.features.hasSignalIndex) {
      return 'driven';
    }
    const cached = this.clockCache.get(name);
    if (cached) {
      return cached.mode;
    }
    const idx = this.get_signal_idx(name);
    if (idx < 0) {
      return 'unknown';
    }
    const listIdx = this.get_clock_list_idx(idx);
    const mode = listIdx >= 0 ? 'forced' : 'driven';
    this.clockCache.set(name, { clockIdx: idx, clockListIdx: listIdx, mode });
    return mode;
  }

  clock_signals_by_name(names) {
    const result = [];
    for (const name of names) {
      if (!name || !this.has_signal(name)) {
        continue;
      }
      result.push({
        name,
        mode: this.clock_mode(name)
      });
    }
    return result;
  }

  clock_signals() {
    const csv = this.simBlob(SIM_BLOB_INPUT_NAMES);
    if (!csv) {
      return [];
    }
    const names = csv.split(',').filter(Boolean);
    return this.clock_signals_by_name(names.filter((n) => /(^|_)clk(_|$)/i.test(n)));
  }

  reset() {
    this.simExec(SIM_EXEC_RESET);
  }

  trace_start() {
    this.traceSnapshot = '';
    return this.simTrace(SIM_TRACE_START).ok;
  }

  trace_start_streaming(path) {
    return this.simTrace(SIM_TRACE_START_STREAMING, path).ok;
  }

  trace_stop() {
    this.simTrace(SIM_TRACE_STOP);
  }

  trace_add_signal(name) {
    return this.simTrace(SIM_TRACE_ADD_SIGNAL, name).ok;
  }

  trace_add_signals_matching(pattern) {
    return this.simTrace(SIM_TRACE_ADD_SIGNALS_MATCHING, pattern).value | 0;
  }

  trace_all_signals() {
    this.simTrace(SIM_TRACE_ALL_SIGNALS);
  }

  trace_clear_signals() {
    this.simTrace(SIM_TRACE_CLEAR_SIGNALS);
  }

  trace_take_live_vcd() {
    const chunk = this.simBlob(SIM_BLOB_TRACE_TAKE_LIVE_VCD);
    if (chunk) {
      return chunk;
    }

    const full = this.trace_to_vcd();
    if (!full) {
      return '';
    }
    if (this.traceSnapshot && full.startsWith(this.traceSnapshot)) {
      const delta = full.slice(this.traceSnapshot.length);
      this.traceSnapshot = full;
      return delta;
    }
    this.traceSnapshot = full;
    return full;
  }

  trace_to_vcd() {
    return this.simBlob(SIM_BLOB_TRACE_TO_VCD);
  }

  trace_clear() {
    this.simTrace(SIM_TRACE_CLEAR);
    this.traceSnapshot = '';
  }

  trace_change_count() {
    return this.simTrace(SIM_TRACE_CHANGE_COUNT).value >>> 0;
  }

  trace_signal_count() {
    return this.simTrace(SIM_TRACE_SIGNAL_COUNT).value >>> 0;
  }

  trace_set_timescale(timescale) {
    return this.simTrace(SIM_TRACE_SET_TIMESCALE, timescale).ok;
  }

  trace_set_module_name(name) {
    return this.simTrace(SIM_TRACE_SET_MODULE_NAME, name).ok;
  }

  withAllocatedBytes(bytes, fn) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return fn(0, 0);
    }
    const ptr = this.alloc(bytes.length);
    try {
      this.u8().set(bytes, ptr);
      return fn(ptr, bytes.length);
    } finally {
      this.dealloc(ptr, bytes.length);
    }
  }

  readBytesViaExport(readFn, offset, length) {
    const len = Math.max(0, Number.parseInt(length, 10) || 0);
    if (len === 0) {
      return new Uint8Array(0);
    }

    const ptr = this.alloc(len);
    try {
      const readLen = readFn(this.ctx, Number(offset) >>> 0, ptr, len) >>> 0;
      return new Uint8Array(this.memoryBuffer().slice(ptr, ptr + readLen));
    } finally {
      this.dealloc(ptr, len);
    }
  }

  readRunnerCaps(capsPtr) {
    const view = new DataView(this.memoryBuffer(), capsPtr, 16);
    return {
      kind: view.getInt32(0, true),
      memSpaces: view.getUint32(4, true),
      controlOps: view.getUint32(8, true),
      probeOps: view.getUint32(12, true)
    };
  }

  runnerCaps() {
    if (this._runnerCaps) {
      return this._runnerCaps;
    }
    if (!this.hasExport('runner_get_caps')) {
      return null;
    }
    const ptr = this.alloc(16);
    try {
      this.u8().fill(0, ptr, ptr + 16);
      const ok = this.e.runner_get_caps(this.ctx, ptr);
      if (ok === 0) {
        return null;
      }
      this._runnerCaps = this.readRunnerCaps(ptr);
      return this._runnerCaps;
    } finally {
      this.dealloc(ptr, 16);
    }
  }

  runnerProbe(op, arg0 = 0) {
    if (!this.hasExport('runner_probe')) {
      return 0;
    }
    const raw = this.e.runner_probe(this.ctx, Number(op) >>> 0, Number(arg0) >>> 0);
    const value = Number(raw);
    return Number.isFinite(value) ? value : 0;
  }

  readRunnerRunResult(resultPtr) {
    const view = new DataView(this.memoryBuffer(), resultPtr, 20);
    return {
      text_dirty: view.getInt32(0, true) !== 0,
      key_cleared: view.getInt32(4, true) !== 0,
      cycles_run: view.getUint32(8, true),
      speaker_toggles: view.getUint32(12, true),
      frames_completed: view.getUint32(16, true)
    };
  }

  runnerMemTransfer(op, space, offset, bytes, flags = 0) {
    if (!this.hasExport('runner_mem')) {
      return 0;
    }
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return 0;
    }
    return this.withAllocatedBytes(bytes, (ptr, len) => (
      this.e.runner_mem(
        this.ctx,
        Number(op) >>> 0,
        Number(space) >>> 0,
        Number(offset) >>> 0,
        ptr,
        len,
        Number(flags) >>> 0
      ) >>> 0
    ));
  }

  runnerMemRead(space, offset, length, flags = 0) {
    if (!this.hasExport('runner_mem')) {
      return new Uint8Array(0);
    }
    const len = Math.max(0, Number.parseInt(length, 10) || 0);
    if (len === 0) {
      return new Uint8Array(0);
    }
    const ptr = this.alloc(len);
    try {
      const readLen = this.e.runner_mem(
        this.ctx,
        RUNNER_MEM_OP_READ,
        Number(space) >>> 0,
        Number(offset) >>> 0,
        ptr,
        len,
        Number(flags) >>> 0
      ) >>> 0;
      return new Uint8Array(this.memoryBuffer().slice(ptr, ptr + readLen));
    } finally {
      this.dealloc(ptr, len);
    }
  }

  runner_kind() {
    const raw = this.runnerProbe(RUNNER_PROBE_KIND) | 0;
    if (raw === RUNNER_KIND_APPLE2) {
      return 'apple2';
    }
    if (raw === RUNNER_KIND_MOS6502) {
      return 'mos6502';
    }
    if (raw === RUNNER_KIND_GAMEBOY) {
      return 'gameboy';
    }
    if (raw === RUNNER_KIND_CPU8BIT) {
      return 'cpu8bit';
    }
    return null;
  }

  runner_mode() {
    return this.runnerProbe(RUNNER_PROBE_IS_MODE) !== 0;
  }

  runner_load_memory(bytes, offset = 0, options = {}) {
    const space = options.isRom ? RUNNER_MEM_SPACE_ROM : RUNNER_MEM_SPACE_MAIN;
    return this.runnerMemTransfer(RUNNER_MEM_OP_LOAD, space, offset, bytes, 0) > 0;
  }

  runner_read_memory(offset, length, options = {}) {
    const flags = options.mapped === false ? 0 : RUNNER_MEM_FLAG_MAPPED;
    return this.runnerMemRead(RUNNER_MEM_SPACE_MAIN, offset, length, flags);
  }

  runner_write_memory(offset, bytes, options = {}) {
    const flags = options.mapped === false ? 0 : RUNNER_MEM_FLAG_MAPPED;
    return this.runnerMemTransfer(RUNNER_MEM_OP_WRITE, RUNNER_MEM_SPACE_MAIN, offset, bytes, flags) > 0;
  }

  runner_load_rom(bytes, offset = 0) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }
    return this.runnerMemTransfer(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_ROM, offset, bytes, 0) > 0;
  }

  runner_load_boot_rom(bytes) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }
    const written = this.runnerMemTransfer(RUNNER_MEM_OP_LOAD, RUNNER_MEM_SPACE_BOOT_ROM, 0, bytes, 0);
    return written > 0 || this.runner_kind() !== 'gameboy';
  }

  runner_set_reset_vector(address) {
    if (!this.hasExport('runner_control')) {
      return false;
    }
    const vector = Number(address);
    if (!Number.isFinite(vector)) {
      return false;
    }
    return this.e.runner_control(
      this.ctx,
      RUNNER_CONTROL_SET_RESET_VECTOR,
      vector & 0xFFFF,
      0
    ) !== 0;
  }

  runner_run_cycles(cycles, keyData = 0, keyReady = false) {
    if (!this.hasExport('runner_run')) {
      return null;
    }
    const resultSize = 20;
    const resultPtr = this.alloc(resultSize);
    try {
      this.u8().fill(0, resultPtr, resultPtr + resultSize);
      const ok = this.e.runner_run(
        this.ctx,
        Math.max(0, Number.parseInt(cycles, 10) || 0),
        Number(keyData) & 0xFF,
        keyReady ? 1 : 0,
        RUNNER_RUN_MODE_BASIC,
        resultPtr
      );
      if (ok === 0) {
        return null;
      }
      const result = this.readRunnerRunResult(resultPtr);
      this.simRunnerSpeakerToggles = (this.simRunnerSpeakerToggles + (result.speaker_toggles >>> 0)) >>> 0;
      return {
        text_dirty: result.text_dirty,
        key_cleared: result.key_cleared,
        cycles_run: result.cycles_run,
        speaker_toggles: result.speaker_toggles
      };
    } finally {
      this.dealloc(resultPtr, resultSize);
    }
  }

  runner_run_cycles_full(cycles) {
    if (!this.hasExport('runner_run')) {
      return { cycles_run: 0, frames_completed: 0 };
    }
    const resultSize = 20;
    const resultPtr = this.alloc(resultSize);
    try {
      this.u8().fill(0, resultPtr, resultPtr + resultSize);
      const ok = this.e.runner_run(
        this.ctx,
        Math.max(0, Number.parseInt(cycles, 10) || 0),
        0,
        0,
        RUNNER_RUN_MODE_FULL,
        resultPtr
      );
      if (ok === 0) {
        return { cycles_run: 0, frames_completed: 0 };
      }
      const result = this.readRunnerRunResult(resultPtr);
      return {
        cycles_run: result.cycles_run,
        frames_completed: result.frames_completed
      };
    } finally {
      this.dealloc(resultPtr, resultSize);
    }
  }

  runner_speaker_toggles() {
    const kind = this.runner_kind();
    if (kind === 'mos6502') {
      return this.runnerProbe(RUNNER_PROBE_SPEAKER_TOGGLES) >>> 0;
    }
    return this.simRunnerSpeakerToggles >>> 0;
  }

  runner_reset_speaker_toggles() {
    if (this.hasExport('runner_control')) {
      this.e.runner_control(this.ctx, RUNNER_CONTROL_RESET_SPEAKER_TOGGLES, 0, 0);
    }
    this.simRunnerSpeakerToggles = 0;
  }

  runner_read_vram(addr) {
    const bytes = this.runnerMemRead(RUNNER_MEM_SPACE_VRAM, addr, 1, 0);
    return bytes.length > 0 ? (bytes[0] & 0xFF) : 0;
  }

  runner_write_vram(addr, value) {
    this.runnerMemTransfer(
      RUNNER_MEM_OP_WRITE,
      RUNNER_MEM_SPACE_VRAM,
      addr,
      new Uint8Array([Number(value) & 0xFF]),
      0
    );
  }

  runner_read_zpram(addr) {
    const bytes = this.runnerMemRead(RUNNER_MEM_SPACE_ZPRAM, addr, 1, 0);
    return bytes.length > 0 ? (bytes[0] & 0xFF) : 0;
  }

  runner_write_zpram(addr, value) {
    this.runnerMemTransfer(
      RUNNER_MEM_OP_WRITE,
      RUNNER_MEM_SPACE_ZPRAM,
      addr,
      new Uint8Array([Number(value) & 0xFF]),
      0
    );
  }

  runner_read_wram(addr) {
    const bytes = this.runnerMemRead(RUNNER_MEM_SPACE_WRAM, addr, 1, 0);
    return bytes.length > 0 ? (bytes[0] & 0xFF) : 0;
  }

  runner_write_wram(addr, value) {
    this.runnerMemTransfer(
      RUNNER_MEM_OP_WRITE,
      RUNNER_MEM_SPACE_WRAM,
      addr,
      new Uint8Array([Number(value) & 0xFF]),
      0
    );
  }

  runner_framebuffer() {
    const len = this.runnerProbe(RUNNER_PROBE_FRAMEBUFFER_LEN) >>> 0;
    if (len === 0) {
      return new Uint8Array(0);
    }
    return this.runnerMemRead(RUNNER_MEM_SPACE_FRAMEBUFFER, 0, len, 0);
  }

  runner_frame_count() {
    return this.runnerProbe(RUNNER_PROBE_FRAME_COUNT) >>> 0;
  }

  runner_reset_lcd() {
    if (this.hasExport('runner_control')) {
      this.e.runner_control(this.ctx, RUNNER_CONTROL_RESET_LCD, 0, 0);
    }
  }

  runner_get_v_cnt() {
    return this.runnerProbe(RUNNER_PROBE_V_CNT) >>> 0;
  }

  runner_get_h_cnt() {
    return this.runnerProbe(RUNNER_PROBE_H_CNT) >>> 0;
  }

  runner_get_vblank_irq() {
    return this.runnerProbe(RUNNER_PROBE_VBLANK_IRQ) >>> 0;
  }

  runner_get_if_r() {
    return this.runnerProbe(RUNNER_PROBE_IF_R) >>> 0;
  }

  runner_get_signal(idx) {
    return this.runnerProbe(RUNNER_PROBE_SIGNAL, idx);
  }

  runner_get_lcdc_on() {
    return this.runnerProbe(RUNNER_PROBE_LCDC_ON) >>> 0;
  }

  runner_get_h_div_cnt() {
    return this.runnerProbe(RUNNER_PROBE_H_DIV_CNT) >>> 0;
  }

  memory_mode() {
    const kind = this.runner_kind();
    if (kind === 'apple2' || kind === 'mos6502' || kind === 'cpu8bit') {
      return kind;
    }
    return null;
  }

  memory_load(bytes, offset = 0, options = {}) {
    return this.runner_load_memory(bytes, offset, options);
  }

  memory_read(offset, length, options = {}) {
    return this.runner_read_memory(offset, length, options);
  }

  memory_write(offset, bytes, options = {}) {
    return this.runner_write_memory(offset, bytes, options);
  }

  memory_read_byte(address, options = {}) {
    const bytes = this.runner_read_memory(address, 1, options);
    return bytes.length > 0 ? (bytes[0] & 0xFF) : 0;
  }

  memory_write_byte(address, value, options = {}) {
    return this.runner_write_memory(address, new Uint8Array([Number(value) & 0xFF]), options);
  }
}
