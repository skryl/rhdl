import { getBackendDef } from './backend_defs.mjs';

export class WasmIrSimulator {
  constructor(instance, irJson, backend = 'interpreter', subCycles = 14) {
    this.instance = instance;
    this.backend = getBackendDef(backend);
    this.e = WasmIrSimulator.normalizeExports(instance.exports, this.backend);
    this.features = this.e.__features || {};
    this.encoder = new TextEncoder();
    this.decoder = new TextDecoder();
    this.ctx = 0;
    this.clockCache = new Map();
    this.traceSnapshot = '';

    this.requireExport('memory');
    this.requireExport('ir_sim_create');
    this.requireExport('ir_sim_destroy');
    this.requireExport('ir_sim_wasm_alloc');
    this.requireExport('ir_sim_wasm_dealloc');

    const jsonBytes = this.encoder.encode(irJson);
    const jsonPtr = this.alloc(jsonBytes.length);
    const errOutPtr = this.alloc(4);

    try {
      this.u8().set(jsonBytes, jsonPtr);
      this.u32().set([0], errOutPtr >>> 2);

      this.ctx = this.e.ir_sim_create(jsonPtr, jsonBytes.length, subCycles, errOutPtr);
      if (this.ctx === 0) {
        const errPtr = this.u32()[errOutPtr >>> 2];
        if (errPtr) {
          const msg = this.readCString(errPtr);
          this.e.ir_sim_free_error(errPtr);
          throw new Error(msg || 'ir_sim_create failed');
        }
        throw new Error('ir_sim_create failed');
      }

      if (typeof this.e.ir_sim_compile === 'function') {
        const compileErrOut = this.alloc(4);
        try {
          this.u32().set([0], compileErrOut >>> 2);
          const compileRc = this.e.ir_sim_compile(this.ctx, compileErrOut);
          if (compileRc < 0) {
            const errPtr = this.u32()[compileErrOut >>> 2];
            if (errPtr) {
              const msg = this.readCString(errPtr);
              this.e.ir_sim_free_error(errPtr);
              throw new Error(msg || 'ir_sim_compile failed');
            }
            throw new Error('ir_sim_compile failed');
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
    const apple2 = backendDef.apple2Prefix;

    const out = {
      memory: raw.memory
    };

    out.ir_sim_create = must(backendDef.createFn, `${core}_create`);
    out.ir_sim_destroy = must(backendDef.destroyFn, `${core}_destroy`);
    out.ir_sim_free_error = must(backendDef.freeErrorFn, `${core}_free_error`);
    out.ir_sim_free_string = must(backendDef.freeStringFn, `${core}_free_string`);
    out.ir_sim_compile = pick(`${core}_compile`);
    out.ir_sim_is_compiled = pick(`${core}_is_compiled`);
    out.ir_sim_wasm_alloc = must(`${alloc}_wasm_alloc`, `${core}_wasm_alloc`);
    out.ir_sim_wasm_dealloc = must(`${alloc}_wasm_dealloc`, `${core}_wasm_dealloc`);

    out.ir_sim_signal_count = must(`${core}_signal_count`);
    out.ir_sim_reg_count = must(`${core}_reg_count`);
    out.ir_sim_input_names = must(`${core}_input_names`);
    out.ir_sim_output_names = must(`${core}_output_names`);
    out.ir_sim_has_signal = must(`${core}_has_signal`);
    out.ir_sim_poke = must(`${core}_poke`);
    out.ir_sim_peek = must(`${core}_peek`);
    out.ir_sim_evaluate = must(`${core}_evaluate`);
    out.ir_sim_tick = must(`${core}_tick`);
    out.ir_sim_reset = must(`${core}_reset`);

    const getSignalIdx = pick(`${core}_get_signal_idx`);
    const pokeByIdx = pick(`${core}_poke_by_idx`);
    const peekByIdx = pick(`${core}_peek_by_idx`);
    const tickForced = pick(`${core}_tick_forced`);
    const setPrevClock = pick(`${core}_set_prev_clock`);
    const getClockListIdx = pick(`${core}_get_clock_list_idx`);

    out.ir_sim_get_signal_idx = getSignalIdx || (() => -1);
    out.ir_sim_poke_by_idx = pokeByIdx || (() => {});
    out.ir_sim_peek_by_idx = peekByIdx || (() => 0);
    out.ir_sim_tick_forced = tickForced || out.ir_sim_tick;
    out.ir_sim_set_prev_clock = setPrevClock || (() => {});
    out.ir_sim_get_clock_list_idx = getClockListIdx || (() => -1);

    out.ir_sim_trace_start = must(`${core}_trace_start`);
    out.ir_sim_trace_start_streaming = pick(`${core}_trace_start_streaming`) || (() => -1);
    out.ir_sim_trace_stop = must(`${core}_trace_stop`);
    out.ir_sim_trace_enabled = must(`${core}_trace_enabled`);
    out.ir_sim_trace_capture = must(`${core}_trace_capture`);
    out.ir_sim_trace_add_signal = must(`${core}_trace_add_signal`);
    out.ir_sim_trace_add_signals_matching = must(`${core}_trace_add_signals_matching`);
    out.ir_sim_trace_all_signals = must(`${core}_trace_all_signals`);
    out.ir_sim_trace_clear_signals = must(`${core}_trace_clear_signals`);
    const traceTakeLiveVcd = pick(`${core}_trace_take_live_vcd`);
    out.ir_sim_trace_take_live_vcd = traceTakeLiveVcd;
    out.ir_sim_trace_to_vcd = must(`${core}_trace_to_vcd`);
    out.ir_sim_trace_clear = must(`${core}_trace_clear`);
    out.ir_sim_trace_change_count = must(`${core}_trace_change_count`);
    out.ir_sim_trace_signal_count = must(`${core}_trace_signal_count`);
    out.ir_sim_trace_set_timescale = must(`${core}_trace_set_timescale`);
    out.ir_sim_trace_set_module_name = must(`${core}_trace_set_module_name`);

    out.apple2_interp_sim_is_mode = pick(`${apple2}_is_mode`);
    out.apple2_interp_sim_load_rom = pick(`${apple2}_load_rom`);
    out.apple2_interp_sim_load_ram = pick(`${apple2}_load_ram`);
    out.apple2_interp_sim_run_cpu_cycles = pick(`${apple2}_run_cpu_cycles`);
    out.apple2_interp_sim_read_ram = pick(`${apple2}_read_ram`);
    out.apple2_interp_sim_read_memory = pick(`${apple2}_read_memory`);
    out.apple2_interp_sim_write_ram = pick(`${apple2}_write_ram`);

    out.__features = {
      hasSignalIndex: !!(getSignalIdx && pokeByIdx && peekByIdx),
      hasForcedClock: !!(getSignalIdx && pokeByIdx && tickForced && setPrevClock && getClockListIdx),
      hasLiveTrace: !!traceTakeLiveVcd,
      requiresCompile: !!out.ir_sim_compile
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
    return this.e.ir_sim_wasm_alloc(Math.max(1, size));
  }

  dealloc(ptr, size) {
    if (ptr) {
      this.e.ir_sim_wasm_dealloc(ptr, Math.max(1, size));
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

  takeOwnedCString(ptr, freeFn = 'ir_sim_free_string') {
    if (!ptr) {
      return '';
    }

    const text = this.readCString(ptr);
    if (this.e[freeFn]) {
      this.e[freeFn](ptr);
    }
    return text;
  }

  destroy() {
    if (this.ctx) {
      this.e.ir_sim_destroy(this.ctx);
      this.ctx = 0;
    }
  }

  signal_count() {
    return this.e.ir_sim_signal_count(this.ctx);
  }

  reg_count() {
    return this.e.ir_sim_reg_count(this.ctx);
  }

  input_names() {
    const ptr = this.e.ir_sim_input_names(this.ctx);
    const csv = this.takeOwnedCString(ptr);
    if (!csv) {
      return [];
    }
    return csv.split(',').filter(Boolean);
  }

  output_names() {
    const ptr = this.e.ir_sim_output_names(this.ctx);
    const csv = this.takeOwnedCString(ptr);
    if (!csv) {
      return [];
    }
    return csv.split(',').filter(Boolean);
  }

  get_signal_idx(name) {
    return this.withCString(name, (ptr) => this.e.ir_sim_get_signal_idx(this.ctx, ptr));
  }

  has_signal(name) {
    return this.withCString(name, (ptr) => this.e.ir_sim_has_signal(this.ctx, ptr) !== 0);
  }

  poke(name, value) {
    return this.withCString(name, (ptr) => this.e.ir_sim_poke(this.ctx, ptr, Number(value)) === 0);
  }

  peek(name) {
    return this.withCString(name, (ptr) => this.e.ir_sim_peek(this.ctx, ptr));
  }

  poke_by_idx(idx, value) {
    this.e.ir_sim_poke_by_idx(this.ctx, idx, Number(value));
  }

  peek_by_idx(idx) {
    return this.e.ir_sim_peek_by_idx(this.ctx, idx);
  }

  trace_enabled() {
    return this.e.ir_sim_trace_enabled(this.ctx) !== 0;
  }

  trace_capture() {
    this.e.ir_sim_trace_capture(this.ctx);
  }

  evaluate() {
    this.e.ir_sim_evaluate(this.ctx);
    if (this.trace_enabled()) {
      this.trace_capture();
    }
  }

  tick() {
    this.e.ir_sim_tick(this.ctx);
    if (this.trace_enabled()) {
      this.trace_capture();
    }
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
      clockListIdx = this.e.ir_sim_get_clock_list_idx(this.ctx, clockIdx);
      mode = clockListIdx >= 0 ? 'forced' : 'driven';
      this.clockCache.set(clockSignal, { clockIdx, clockListIdx, mode });
    }

    const n = Math.max(0, Number.parseInt(cycles, 10) || 0);

    if (mode === 'forced') {
      const traceOn = this.trace_enabled();
      for (let i = 0; i < n; i += 1) {
        this.e.ir_sim_set_prev_clock(this.ctx, clockListIdx, 0);
        this.e.ir_sim_poke_by_idx(this.ctx, clockIdx, 1);
        this.e.ir_sim_tick_forced(this.ctx);
        if (traceOn) {
          this.trace_capture();
        }

        this.e.ir_sim_poke_by_idx(this.ctx, clockIdx, 0);
        this.e.ir_sim_evaluate(this.ctx);
        if (traceOn) {
          this.trace_capture();
        }
      }
      return;
    }

    // Driven mode: toggle an external/root clock and let evaluate()+tick()
    // propagate edges to all derived internal clock domains.
    for (let i = 0; i < n; i += 1) {
      this.e.ir_sim_poke_by_idx(this.ctx, clockIdx, 0);
      this.evaluate();
      this.e.ir_sim_poke_by_idx(this.ctx, clockIdx, 1);
      this.tick();
      this.e.ir_sim_poke_by_idx(this.ctx, clockIdx, 0);
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
    const listIdx = this.e.ir_sim_get_clock_list_idx(this.ctx, idx);
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
    const ptr = this.e.ir_sim_input_names(this.ctx);
    const csv = this.takeOwnedCString(ptr);
    if (!csv) {
      return [];
    }
    const names = csv.split(',').filter(Boolean);
    return this.clock_signals_by_name(names.filter((n) => /(^|_)clk(_|$)/i.test(n)));
  }

  reset() {
    this.e.ir_sim_reset(this.ctx);
  }

  trace_start() {
    this.traceSnapshot = '';
    return this.e.ir_sim_trace_start(this.ctx) === 0;
  }

  trace_start_streaming(path) {
    return this.withCString(path, (ptr) => this.e.ir_sim_trace_start_streaming(this.ctx, ptr) === 0);
  }

  trace_stop() {
    this.e.ir_sim_trace_stop(this.ctx);
  }

  trace_add_signal(name) {
    return this.withCString(name, (ptr) => this.e.ir_sim_trace_add_signal(this.ctx, ptr) === 0);
  }

  trace_add_signals_matching(pattern) {
    return this.withCString(pattern, (ptr) => this.e.ir_sim_trace_add_signals_matching(this.ctx, ptr));
  }

  trace_all_signals() {
    this.e.ir_sim_trace_all_signals(this.ctx);
  }

  trace_clear_signals() {
    this.e.ir_sim_trace_clear_signals(this.ctx);
  }

  trace_take_live_vcd() {
    if (typeof this.e.ir_sim_trace_take_live_vcd === 'function') {
      const ptr = this.e.ir_sim_trace_take_live_vcd(this.ctx);
      return this.takeOwnedCString(ptr);
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
    const ptr = this.e.ir_sim_trace_to_vcd(this.ctx);
    return this.takeOwnedCString(ptr);
  }

  trace_clear() {
    this.e.ir_sim_trace_clear(this.ctx);
    this.traceSnapshot = '';
  }

  trace_change_count() {
    return this.e.ir_sim_trace_change_count(this.ctx);
  }

  trace_signal_count() {
    return this.e.ir_sim_trace_signal_count(this.ctx);
  }

  trace_set_timescale(timescale) {
    return this.withCString(timescale, (ptr) => this.e.ir_sim_trace_set_timescale(this.ctx, ptr) === 0);
  }

  trace_set_module_name(name) {
    return this.withCString(name, (ptr) => this.e.ir_sim_trace_set_module_name(this.ctx, ptr) === 0);
  }

  apple2_mode() {
    if (!this.hasExport('apple2_interp_sim_is_mode')) {
      return false;
    }
    return this.e.apple2_interp_sim_is_mode(this.ctx) !== 0;
  }

  apple2_load_rom(bytes) {
    if (!this.hasExport('apple2_interp_sim_load_rom')) {
      return false;
    }
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }
    const ptr = this.alloc(bytes.length);
    try {
      this.u8().set(bytes, ptr);
      this.e.apple2_interp_sim_load_rom(this.ctx, ptr, bytes.length);
      return true;
    } finally {
      this.dealloc(ptr, bytes.length);
    }
  }

  apple2_load_ram(bytes, offset = 0) {
    if (!this.hasExport('apple2_interp_sim_load_ram')) {
      return false;
    }
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }
    const ptr = this.alloc(bytes.length);
    try {
      this.u8().set(bytes, ptr);
      this.e.apple2_interp_sim_load_ram(this.ctx, ptr, bytes.length, Number(offset) >>> 0);
      return true;
    } finally {
      this.dealloc(ptr, bytes.length);
    }
  }

  apple2_run_cpu_cycles(cycles, keyData = 0, keyReady = false) {
    if (!this.hasExport('apple2_interp_sim_run_cpu_cycles')) {
      return null;
    }

    const resultSize = 16;
    const resultPtr = this.alloc(resultSize);
    try {
      this.u8().fill(0, resultPtr, resultPtr + resultSize);
      this.e.apple2_interp_sim_run_cpu_cycles(
        this.ctx,
        Math.max(0, Number.parseInt(cycles, 10) || 0),
        Number(keyData) & 0xff,
        keyReady ? 1 : 0,
        resultPtr
      );

      const view = new DataView(this.memoryBuffer(), resultPtr, resultSize);
      return {
        text_dirty: view.getInt32(0, true) !== 0,
        key_cleared: view.getInt32(4, true) !== 0,
        cycles_run: view.getUint32(8, true),
        speaker_toggles: view.getUint32(12, true)
      };
    } finally {
      this.dealloc(resultPtr, resultSize);
    }
  }

  apple2_read_ram(offset, length) {
    if (!this.hasExport('apple2_interp_sim_read_ram')) {
      return new Uint8Array(0);
    }
    const len = Math.max(0, Number.parseInt(length, 10) || 0);
    if (len === 0) {
      return new Uint8Array(0);
    }

    const ptr = this.alloc(len);
    try {
      const readLen = this.e.apple2_interp_sim_read_ram(this.ctx, Number(offset) >>> 0, ptr, len) >>> 0;
      return new Uint8Array(this.memoryBuffer().slice(ptr, ptr + readLen));
    } finally {
      this.dealloc(ptr, len);
    }
  }

  apple2_read_memory(offset, length) {
    const len = Math.max(0, Number.parseInt(length, 10) || 0);
    if (len === 0) {
      return new Uint8Array(0);
    }
    if (!this.hasExport('apple2_interp_sim_read_memory')) {
      return this.apple2_read_ram(offset, len);
    }

    const ptr = this.alloc(len);
    try {
      const readLen = this.e.apple2_interp_sim_read_memory(this.ctx, Number(offset) >>> 0, ptr, len) >>> 0;
      return new Uint8Array(this.memoryBuffer().slice(ptr, ptr + readLen));
    } finally {
      this.dealloc(ptr, len);
    }
  }

  apple2_write_ram(offset, bytes) {
    if (!this.hasExport('apple2_interp_sim_write_ram')) {
      return false;
    }
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return false;
    }

    const ptr = this.alloc(bytes.length);
    try {
      this.u8().set(bytes, ptr);
      this.e.apple2_interp_sim_write_ram(this.ctx, Number(offset) >>> 0, ptr, bytes.length);
      return true;
    } finally {
      this.dealloc(ptr, bytes.length);
    }
  }
}
