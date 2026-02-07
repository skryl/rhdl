const BACKEND_DEFS = {
  interpreter: {
    id: 'interpreter',
    label: 'Interpreter',
    wasmPath: './pkg/ir_interpreter.wasm',
    corePrefix: 'ir_sim',
    allocPrefix: 'ir_sim',
    apple2Prefix: 'apple2_interp_sim',
    createFn: 'ir_sim_create',
    destroyFn: 'ir_sim_destroy',
    freeErrorFn: 'ir_sim_free_error',
    freeStringFn: 'ir_sim_free_string'
  },
  jit: {
    id: 'jit',
    label: 'JIT',
    wasmPath: './pkg/ir_jit.wasm',
    corePrefix: 'jit_sim',
    allocPrefix: 'jit_sim',
    apple2Prefix: 'apple2_jit_sim',
    createFn: 'jit_sim_create',
    destroyFn: 'jit_sim_destroy',
    freeErrorFn: 'jit_sim_free_error',
    freeStringFn: 'jit_sim_free_string'
  },
  compiler: {
    id: 'compiler',
    label: 'Compiler (AOT)',
    wasmPath: './pkg/ir_compiler.wasm',
    corePrefix: 'ir_sim',
    allocPrefix: 'ir_sim',
    apple2Prefix: 'apple2_ir_sim',
    createFn: 'ir_sim_create',
    destroyFn: 'ir_sim_destroy',
    freeErrorFn: 'ir_sim_free_error',
    freeStringFn: 'ir_sim_free_string'
  }
};

function getBackendDef(id) {
  if (id && BACKEND_DEFS[id]) {
    return BACKEND_DEFS[id];
  }
  return BACKEND_DEFS.interpreter;
}

class WasmIrSimulator {
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

class LiveVcdParser {
  constructor(maxPoints = 5000) {
    this.maxPoints = maxPoints;
    this.reset();
  }

  reset() {
    this.signalIds = new Map();
    this.signalWidths = new Map();
    this.traces = new Map();
    this.latestValues = new Map();
    this.time = 0;
    this.partial = '';
  }

  ingest(chunk) {
    if (!chunk) {
      return;
    }

    const data = this.partial + chunk;
    const lines = data.split('\n');
    this.partial = lines.pop() || '';

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }
      this.parseLine(line);
    }
  }

  parseLine(line) {
    if (line.startsWith('$var')) {
      const m = line.match(/^\$var\s+wire\s+(\d+)\s+(\S+)\s+(\S+)\s+\$end$/);
      if (m) {
        const width = Number.parseInt(m[1], 10);
        const id = m[2];
        const name = m[3];
        this.signalIds.set(id, name);
        this.signalWidths.set(name, width);
        if (!this.traces.has(name)) {
          this.traces.set(name, []);
        }
      }
      return;
    }

    if (line[0] === '#') {
      const t = Number.parseInt(line.slice(1), 10);
      if (Number.isFinite(t)) {
        this.time = t;
      }
      return;
    }

    if (line[0] === 'b') {
      const m = line.match(/^b([01xz]+)\s+(\S+)$/i);
      if (!m) {
        return;
      }
      const bits = m[1].replace(/[xz]/gi, '0');
      const id = m[2];
      const value = bits.length > 30 ? Number.parseInt(bits.slice(-30), 2) : Number.parseInt(bits, 2);
      this.record(id, Number.isFinite(value) ? value : 0);
      return;
    }

    if (line[0] === '0' || line[0] === '1') {
      const value = line[0] === '1' ? 1 : 0;
      const id = line.slice(1);
      this.record(id, value);
    }
  }

  record(id, value) {
    const name = this.signalIds.get(id);
    if (!name) {
      return;
    }

    const trace = this.traces.get(name) || [];
    const last = trace[trace.length - 1];
    if (!last || last.t !== this.time || last.v !== value) {
      trace.push({ t: this.time, v: value });
      if (trace.length > this.maxPoints) {
        trace.splice(0, trace.length - this.maxPoints);
      }
      this.traces.set(name, trace);
    }

    this.latestValues.set(name, value);
  }

  series(name) {
    return this.traces.get(name) || [];
  }

  value(name) {
    return this.latestValues.get(name);
  }

  latestTime() {
    return this.time;
  }
}

const dom = {
  appShell: document.getElementById('appShell'),
  viewer: document.querySelector('.viewer'),
  controlsPanel: document.getElementById('controlsPanel'),
  sidebarToggleBtn: document.getElementById('sidebarToggleBtn'),
  terminalToggleBtn: document.getElementById('terminalToggleBtn'),
  terminalPanel: document.getElementById('terminalPanel'),
  terminalOutput: document.getElementById('terminalOutput'),
  terminalInput: document.getElementById('terminalInput'),
  terminalRunBtn: document.getElementById('terminalRunBtn'),
  backendSelect: document.getElementById('backendSelect'),
  backendStatus: document.getElementById('backendStatus'),
  themeSelect: document.getElementById('themeSelect'),
  runnerSelect: document.getElementById('runnerSelect'),
  loadRunnerBtn: document.getElementById('loadRunnerBtn'),
  runnerStatus: document.getElementById('runnerStatus'),
  irSourceSection: document.getElementById('irSourceSection'),
  tabButtons: Array.from(document.querySelectorAll('.tab-btn')),
  tabPanels: Array.from(document.querySelectorAll('.tab-panel')),
  irJson: document.getElementById('irJson'),
  irFileInput: document.getElementById('irFileInput'),
  sampleSelect: document.getElementById('sampleSelect'),
  loadSampleBtn: document.getElementById('loadSampleBtn'),
  initBtn: document.getElementById('initBtn'),
  resetBtn: document.getElementById('resetBtn'),
  stepBtn: document.getElementById('stepBtn'),
  runBtn: document.getElementById('runBtn'),
  pauseBtn: document.getElementById('pauseBtn'),
  stepTicks: document.getElementById('stepTicks'),
  runBatch: document.getElementById('runBatch'),
  uiUpdateCycles: document.getElementById('uiUpdateCycles'),
  clockSignal: document.getElementById('clockSignal'),
  simStatus: document.getElementById('simStatus'),
  traceStatus: document.getElementById('traceStatus'),
  traceStartBtn: document.getElementById('traceStartBtn'),
  traceStopBtn: document.getElementById('traceStopBtn'),
  traceClearBtn: document.getElementById('traceClearBtn'),
  downloadVcdBtn: document.getElementById('downloadVcdBtn'),
  watchSignal: document.getElementById('watchSignal'),
  addWatchBtn: document.getElementById('addWatchBtn'),
  watchList: document.getElementById('watchList'),
  bpSignal: document.getElementById('bpSignal'),
  bpValue: document.getElementById('bpValue'),
  addBpBtn: document.getElementById('addBpBtn'),
  clearBpBtn: document.getElementById('clearBpBtn'),
  bpList: document.getElementById('bpList'),
  watchTableBody: document.getElementById('watchTableBody'),
  eventLog: document.getElementById('eventLog'),
  canvasWrap: document.getElementById('canvasWrap'),
  apple2TextScreen: document.getElementById('apple2TextScreen'),
  apple2HiresCanvas: document.getElementById('apple2HiresCanvas'),
  apple2KeyInput: document.getElementById('apple2KeyInput'),
  apple2SendKeyBtn: document.getElementById('apple2SendKeyBtn'),
  apple2ClearKeysBtn: document.getElementById('apple2ClearKeysBtn'),
  apple2KeyStatus: document.getElementById('apple2KeyStatus'),
  apple2DebugBody: document.getElementById('apple2DebugBody'),
  apple2SpeakerToggles: document.getElementById('apple2SpeakerToggles'),
  toggleHires: document.getElementById('toggleHires'),
  toggleColor: document.getElementById('toggleColor'),
  toggleSound: document.getElementById('toggleSound'),
  memoryDumpFile: document.getElementById('memoryDumpFile'),
  memoryDumpOffset: document.getElementById('memoryDumpOffset'),
  memoryDumpLoadBtn: document.getElementById('memoryDumpLoadBtn'),
  memoryDumpSaveBtn: document.getElementById('memoryDumpSaveBtn'),
  memorySnapshotSaveBtn: document.getElementById('memorySnapshotSaveBtn'),
  memoryDumpLoadLastBtn: document.getElementById('memoryDumpLoadLastBtn'),
  memoryResetVector: document.getElementById('memoryResetVector'),
  memoryResetBtn: document.getElementById('memoryResetBtn'),
  loadKaratekaBtn: document.getElementById('loadKaratekaBtn'),
  memoryDumpStatus: document.getElementById('memoryDumpStatus'),
  memoryStart: document.getElementById('memoryStart'),
  memoryLength: document.getElementById('memoryLength'),
  memoryFollowPc: document.getElementById('memoryFollowPc'),
  memoryRefreshBtn: document.getElementById('memoryRefreshBtn'),
  memoryDump: document.getElementById('memoryDump'),
  memoryDisassembly: document.getElementById('memoryDisassembly'),
  memoryWriteAddr: document.getElementById('memoryWriteAddr'),
  memoryWriteValue: document.getElementById('memoryWriteValue'),
  memoryWriteBtn: document.getElementById('memoryWriteBtn'),
  memoryStatus: document.getElementById('memoryStatus'),
  componentSearch: document.getElementById('componentSearch'),
  componentSearchClearBtn: document.getElementById('componentSearchClearBtn'),
  componentTree: document.getElementById('componentTree'),
  componentTitle: document.getElementById('componentTitle'),
  componentMeta: document.getElementById('componentMeta'),
  componentSignalMeta: document.getElementById('componentSignalMeta'),
  componentSignalBody: document.getElementById('componentSignalBody'),
  componentCodeViewRhdl: document.getElementById('componentCodeViewRhdl'),
  componentCodeViewVerilog: document.getElementById('componentCodeViewVerilog'),
  componentGraphTitle: document.getElementById('componentGraphTitle'),
  componentGraphMeta: document.getElementById('componentGraphMeta'),
  componentGraphTopBtn: document.getElementById('componentGraphTopBtn'),
  componentGraphUpBtn: document.getElementById('componentGraphUpBtn'),
  componentGraphFocusPath: document.getElementById('componentGraphFocusPath'),
  componentVisual: document.getElementById('componentVisual'),
  componentLiveSignals: document.getElementById('componentLiveSignals'),
  componentConnectionMeta: document.getElementById('componentConnectionMeta'),
  componentConnectionBody: document.getElementById('componentConnectionBody'),
  componentCode: document.getElementById('componentCode')
};

const state = {
  instance: null,
  backendInstances: new Map(),
  backend: 'compiler',
  theme: 'shenzhen',
  sidebarCollapsed: false,
  terminalOpen: false,
  sim: null,
  running: false,
  waveformP5: null,
  parser: new LiveVcdParser(),
  cycle: 0,
  uiCyclesPending: 0,
  irMeta: null,
  watches: new Map(),
  watchRows: [],
  breakpoints: [],
  runnerPreset: 'apple2',
  activeTab: 'ioTab',
  apple2: {
    enabled: false,
    keyQueue: [],
    lastSpeakerToggles: 0,
    lastCpuResult: null,
    baseRomBytes: null,
    displayHires: false,
    displayColor: false,
    soundEnabled: false,
    audioCtx: null,
    audioOsc: null,
    audioGain: null
  },
  memory: {
    followPc: false,
    disasmLines: 28,
    lastSavedDump: null
  },
  terminal: {
    history: [],
    historyIndex: -1,
    busy: false
  },
  dashboard: {
    rootElements: new Map(),
    layouts: {},
    draggingItemId: '',
    draggingRootKey: '',
    dropTargetItemId: '',
    dropPosition: '',
    resizeBound: false,
    resizing: {
      active: false,
      rootKey: '',
      rowSignature: '',
      startY: 0,
      startHeight: 140
    }
  },
  components: {
    model: null,
    selectedNodeId: null,
    filter: '',
    parseError: '',
    sourceKey: '',
    overrideSource: '',
    overrideMeta: null,
    graph: null,
    graphKey: '',
    graphSelectedId: null,
    graphFocusId: null,
    graphShowChildren: false,
    graphLastTap: null,
    graphHighlightedSignal: null,
    graphLiveValues: new Map(),
    graphLayoutEngine: 'none',
    graphElkAvailable: false,
    sourceBundle: null,
    sourceBundleByClass: new Map(),
    sourceBundleByModule: new Map(),
    schematicBundle: null,
    schematicBundleByPath: new Map(),
    codeView: 'rhdl'
  }
};

const RUNNER_PRESETS = {
  generic: {
    id: 'generic',
    label: 'Generic IR Runner',
    samplePath: './samples/toggle.json',
    preferredTab: 'vcdTab',
    enableApple2Ui: false,
    usesManualIr: true
  },
  cpu: {
    id: 'cpu',
    label: 'CPU (lib/rhdl/hdl/cpu)',
    simIrPath: './samples/cpu_lib_hdl.json',
    explorerIrPath: './samples/cpu_hier.json',
    sourceBundlePath: './samples/cpu_sources.json',
    schematicPath: './samples/cpu_schematic.json',
    preferredTab: 'vcdTab',
    enableApple2Ui: false,
    usesManualIr: false
  },
  apple2: {
    id: 'apple2',
    label: 'Apple II System Runner',
    simIrPath: './samples/apple2.json',
    explorerIrPath: './samples/apple2_hier.json',
    sourceBundlePath: './samples/apple2_sources.json',
    schematicPath: './samples/apple2_schematic.json',
    romPath: './samples/appleiigo.rom',
    preferredTab: 'ioTab',
    enableApple2Ui: true,
    usesManualIr: false
  }
};

const APPLE2_RAM_BYTES = 48 * 1024;
const APPLE2_ADDR_SPACE = 0x10000;
const KARATEKA_PC = 0xB82A;
const LAST_APPLE2_DUMP_KEY = 'rhdl.apple2.last_memory_dump.v1';
const APPLE2_SNAPSHOT_KIND = 'rhdl.apple2.ram_snapshot';
const APPLE2_SNAPSHOT_VERSION = 1;
const SIDEBAR_COLLAPSED_KEY = 'rhdl.ir.web.sidebar.collapsed.v1';
const TERMINAL_OPEN_KEY = 'rhdl.ir.web.terminal.open.v1';
const THEME_KEY = 'rhdl.ir.web.theme.v1';
const COMPONENT_SIGNAL_PREVIEW_LIMIT = 180;
const COLLAPSIBLE_PANEL_SELECTOR = '#controlsPanel > section, .subpanel';
const DASHBOARD_LAYOUT_KEY = 'rhdl.ir.web.dashboard.layout.v1';
const DASHBOARD_DROP_POSITIONS = new Set(['left', 'right', 'above', 'below']);
const DASHBOARD_MIN_ROW_HEIGHT = 140;
const DASHBOARD_ROOT_CONFIGS = [
  {
    key: 'controls',
    selector: '#controlsPanel',
    panelSelector: ':scope > section',
    flattenPanels: false,
    staticSelectors: [],
    cleanupSelectors: [],
    wrapControls: true
  },
  {
    key: 'ioTab',
    selector: '#ioTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: [],
    cleanupSelectors: ['.io-layout']
  },
  {
    key: 'vcdTab',
    selector: '#vcdTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: ['#canvasWrap'],
    cleanupSelectors: ['.vcd-control-grid']
  },
  {
    key: 'memoryTab',
    selector: '#memoryTab',
    panelSelector: ':scope > .subpanel',
    flattenPanels: false,
    staticSelectors: [],
    cleanupSelectors: []
  },
  {
    key: 'componentTab',
    selector: '#componentTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: [],
    cleanupSelectors: ['.component-layout', '.component-left', '.component-right']
  },
  {
    key: 'componentGraphTab',
    selector: '#componentGraphTab',
    panelSelector: '.subpanel',
    flattenPanels: true,
    staticSelectors: [],
    cleanupSelectors: ['.component-graph-layout']
  }
];

// Shared 6502 mnemonic table (matches examples/mos6502/hdl/harness.rb)
const MOS6502_MNEMONICS = {
  0x00: ['BRK', 'imp'], 0x01: ['ORA', 'indx'], 0x05: ['ORA', 'zp'],
  0x06: ['ASL', 'zp'], 0x08: ['PHP', 'imp'], 0x09: ['ORA', 'imm'],
  0x0A: ['ASL', 'acc'], 0x0D: ['ORA', 'abs'], 0x0E: ['ASL', 'abs'],
  0x10: ['BPL', 'rel'], 0x11: ['ORA', 'indy'], 0x15: ['ORA', 'zpx'],
  0x16: ['ASL', 'zpx'], 0x18: ['CLC', 'imp'], 0x19: ['ORA', 'absy'],
  0x1D: ['ORA', 'absx'], 0x1E: ['ASL', 'absx'],
  0x20: ['JSR', 'abs'], 0x21: ['AND', 'indx'], 0x24: ['BIT', 'zp'],
  0x25: ['AND', 'zp'], 0x26: ['ROL', 'zp'], 0x28: ['PLP', 'imp'],
  0x29: ['AND', 'imm'], 0x2A: ['ROL', 'acc'], 0x2C: ['BIT', 'abs'],
  0x2D: ['AND', 'abs'], 0x2E: ['ROL', 'abs'], 0x30: ['BMI', 'rel'],
  0x31: ['AND', 'indy'], 0x35: ['AND', 'zpx'], 0x36: ['ROL', 'zpx'],
  0x38: ['SEC', 'imp'], 0x39: ['AND', 'absy'], 0x3D: ['AND', 'absx'],
  0x3E: ['ROL', 'absx'],
  0x40: ['RTI', 'imp'], 0x41: ['EOR', 'indx'], 0x45: ['EOR', 'zp'],
  0x46: ['LSR', 'zp'], 0x48: ['PHA', 'imp'], 0x49: ['EOR', 'imm'],
  0x4A: ['LSR', 'acc'], 0x4C: ['JMP', 'abs'], 0x4D: ['EOR', 'abs'],
  0x4E: ['LSR', 'abs'], 0x50: ['BVC', 'rel'], 0x51: ['EOR', 'indy'],
  0x55: ['EOR', 'zpx'], 0x56: ['LSR', 'zpx'], 0x58: ['CLI', 'imp'],
  0x59: ['EOR', 'absy'], 0x5D: ['EOR', 'absx'], 0x5E: ['LSR', 'absx'],
  0x60: ['RTS', 'imp'], 0x61: ['ADC', 'indx'], 0x65: ['ADC', 'zp'],
  0x66: ['ROR', 'zp'], 0x68: ['PLA', 'imp'], 0x69: ['ADC', 'imm'],
  0x6A: ['ROR', 'acc'], 0x6C: ['JMP', 'ind'], 0x6D: ['ADC', 'abs'],
  0x6E: ['ROR', 'abs'], 0x70: ['BVS', 'rel'], 0x71: ['ADC', 'indy'],
  0x75: ['ADC', 'zpx'], 0x76: ['ROR', 'zpx'], 0x78: ['SEI', 'imp'],
  0x79: ['ADC', 'absy'], 0x7D: ['ADC', 'absx'], 0x7E: ['ROR', 'absx'],
  0x81: ['STA', 'indx'], 0x84: ['STY', 'zp'], 0x85: ['STA', 'zp'],
  0x86: ['STX', 'zp'], 0x88: ['DEY', 'imp'], 0x8A: ['TXA', 'imp'],
  0x8C: ['STY', 'abs'], 0x8D: ['STA', 'abs'], 0x8E: ['STX', 'abs'],
  0x90: ['BCC', 'rel'], 0x91: ['STA', 'indy'], 0x94: ['STY', 'zpx'],
  0x95: ['STA', 'zpx'], 0x96: ['STX', 'zpy'], 0x98: ['TYA', 'imp'],
  0x99: ['STA', 'absy'], 0x9A: ['TXS', 'imp'], 0x9D: ['STA', 'absx'],
  0xA0: ['LDY', 'imm'], 0xA1: ['LDA', 'indx'], 0xA2: ['LDX', 'imm'],
  0xA4: ['LDY', 'zp'], 0xA5: ['LDA', 'zp'], 0xA6: ['LDX', 'zp'],
  0xA8: ['TAY', 'imp'], 0xA9: ['LDA', 'imm'], 0xAA: ['TAX', 'imp'],
  0xAC: ['LDY', 'abs'], 0xAD: ['LDA', 'abs'], 0xAE: ['LDX', 'abs'],
  0xB0: ['BCS', 'rel'], 0xB1: ['LDA', 'indy'], 0xB4: ['LDY', 'zpx'],
  0xB5: ['LDA', 'zpx'], 0xB6: ['LDX', 'zpy'], 0xB8: ['CLV', 'imp'],
  0xB9: ['LDA', 'absy'], 0xBA: ['TSX', 'imp'], 0xBC: ['LDY', 'absx'],
  0xBD: ['LDA', 'absx'], 0xBE: ['LDX', 'absy'],
  0xC0: ['CPY', 'imm'], 0xC1: ['CMP', 'indx'], 0xC4: ['CPY', 'zp'],
  0xC5: ['CMP', 'zp'], 0xC6: ['DEC', 'zp'], 0xC8: ['INY', 'imp'],
  0xC9: ['CMP', 'imm'], 0xCA: ['DEX', 'imp'], 0xCC: ['CPY', 'abs'],
  0xCD: ['CMP', 'abs'], 0xCE: ['DEC', 'abs'], 0xD0: ['BNE', 'rel'],
  0xD1: ['CMP', 'indy'], 0xD5: ['CMP', 'zpx'], 0xD6: ['DEC', 'zpx'],
  0xD8: ['CLD', 'imp'], 0xD9: ['CMP', 'absy'], 0xDD: ['CMP', 'absx'],
  0xDE: ['DEC', 'absx'],
  0xE0: ['CPX', 'imm'], 0xE1: ['SBC', 'indx'], 0xE4: ['CPX', 'zp'],
  0xE5: ['SBC', 'zp'], 0xE6: ['INC', 'zp'], 0xE8: ['INX', 'imp'],
  0xE9: ['SBC', 'imm'], 0xEA: ['NOP', 'imp'], 0xEC: ['CPX', 'abs'],
  0xED: ['SBC', 'abs'], 0xEE: ['INC', 'abs'], 0xF0: ['BEQ', 'rel'],
  0xF1: ['SBC', 'indy'], 0xF5: ['SBC', 'zpx'], 0xF6: ['INC', 'zpx'],
  0xF8: ['SED', 'imp'], 0xF9: ['SBC', 'absy'], 0xFD: ['SBC', 'absx'],
  0xFE: ['INC', 'absx']
};

function log(message) {
  const ts = new Date().toLocaleTimeString();
  dom.eventLog.textContent = `[${ts}] ${message}\n${dom.eventLog.textContent}`;
}

function toBigInt(value) {
  if (typeof value === 'bigint') {
    return value;
  }
  if (Number.isFinite(value)) {
    return BigInt(Math.trunc(value));
  }
  return 0n;
}

function parseNumeric(text) {
  const raw = String(text || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }

  try {
    if (raw.startsWith('0x')) {
      return BigInt(raw);
    }
    if (raw.startsWith('0b')) {
      return BigInt(raw);
    }
    return BigInt(raw);
  } catch (_err) {
    return null;
  }
}

function formatValue(value, width) {
  if (value == null) {
    return '-';
  }

  const v = toBigInt(value);
  if (width <= 1) {
    return String(Number(v & 1n));
  }

  return `0x${v.toString(16)}`;
}

function terminalWriteLine(message = '') {
  if (!dom.terminalOutput) {
    return;
  }
  const text = String(message ?? '');
  dom.terminalOutput.textContent += `${text}\n`;
  const lines = dom.terminalOutput.textContent.split('\n');
  if (lines.length > 900) {
    dom.terminalOutput.textContent = `${lines.slice(lines.length - 900).join('\n')}\n`;
  }
  dom.terminalOutput.scrollTop = dom.terminalOutput.scrollHeight;
}

function terminalClear() {
  if (!dom.terminalOutput) {
    return;
  }
  dom.terminalOutput.textContent = '';
}

function tokenizeCommandLine(line) {
  const out = [];
  let current = '';
  let quote = '';
  let escaping = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (escaping) {
      current += ch;
      escaping = false;
      continue;
    }
    if (ch === '\\') {
      escaping = true;
      continue;
    }
    if (quote) {
      if (ch === quote) {
        quote = '';
      } else {
        current += ch;
      }
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (/\s/.test(ch)) {
      if (current) {
        out.push(current);
        current = '';
      }
      continue;
    }
    current += ch;
  }

  if (escaping) {
    current += '\\';
  }
  if (quote) {
    throw new Error('Unclosed quote in command.');
  }
  if (current) {
    out.push(current);
  }
  return out;
}

function parseBooleanToken(token) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (['1', 'true', 'on', 'yes', 'enable', 'enabled', 'show', 'open'].includes(raw)) {
    return true;
  }
  if (['0', 'false', 'off', 'no', 'disable', 'disabled', 'hide', 'close'].includes(raw)) {
    return false;
  }
  return null;
}

function normalizeUiId(value) {
  return String(value || '').trim().replace(/^#/, '');
}

function setUiInputValueById(id, value) {
  const elementId = normalizeUiId(id);
  if (!elementId) {
    throw new Error('Missing element id.');
  }
  const el = document.getElementById(elementId);
  if (!(el instanceof HTMLElement)) {
    throw new Error(`Unknown element: ${elementId}`);
  }

  if (el instanceof HTMLInputElement && el.type === 'checkbox') {
    const parsed = parseBooleanToken(value);
    if (parsed == null) {
      throw new Error(`Invalid checkbox value for ${elementId}: ${value}`);
    }
    el.checked = parsed;
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return `set #${elementId}= ${parsed ? 'on' : 'off'}`;
  }

  if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
    el.value = String(value ?? '');
    el.dispatchEvent(new Event('input', { bubbles: true }));
    if (el instanceof HTMLInputElement && (el.type === 'number' || el.type === 'range')) {
      el.dispatchEvent(new Event('change', { bubbles: true }));
    }
    return `set #${elementId}= ${el.value}`;
  }

  if (el instanceof HTMLSelectElement) {
    const next = String(value ?? '');
    const hasOption = Array.from(el.options).some((opt) => opt.value === next);
    if (!hasOption) {
      const options = Array.from(el.options).map((opt) => opt.value).join(', ');
      throw new Error(`Invalid option for ${elementId}. Available: ${options}`);
    }
    el.value = next;
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return `set #${elementId}= ${el.value}`;
  }

  throw new Error(`Element does not support value assignment: ${elementId}`);
}

function clickUiElementById(id) {
  const elementId = normalizeUiId(id);
  if (!elementId) {
    throw new Error('Missing element id.');
  }
  const el = document.getElementById(elementId);
  if (!(el instanceof HTMLElement)) {
    throw new Error(`Unknown element: ${elementId}`);
  }
  if (typeof el.click !== 'function') {
    throw new Error(`Element is not clickable: ${elementId}`);
  }
  el.click();
  return `clicked #${elementId}`;
}

function parseTabToken(token) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  const map = {
    io: 'ioTab',
    'i/o': 'ioTab',
    vcd: 'vcdTab',
    signals: 'vcdTab',
    memory: 'memoryTab',
    mem: 'memoryTab',
    component: 'componentTab',
    components: 'componentTab',
    comp: 'componentTab',
    schematic: 'componentGraphTab',
    graph: 'componentGraphTab'
  };
  if (map[raw]) {
    return map[raw];
  }
  if (dom.tabPanels.some((panel) => panel.id === token)) {
    return token;
  }
  return null;
}

function parseRunnerToken(token) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (RUNNER_PRESETS[raw]) {
    return RUNNER_PRESETS[raw].id;
  }
  if (raw === 'apple' || raw === 'apple2') {
    return 'apple2';
  }
  return null;
}

function parseBackendToken(token) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (BACKEND_DEFS[raw]) {
    return BACKEND_DEFS[raw].id;
  }
  return null;
}

function terminalStatusText() {
  const runner = currentRunnerPreset();
  const backend = getBackendDef(state.backend);
  const tab = state.activeTab || '-';
  const sim = state.sim ? 'ready' : 'not-initialized';
  const trace = state.sim ? (state.sim.trace_enabled() ? 'on' : 'off') : 'n/a';
  return [
    `runner=${runner.id}`,
    `backend=${backend.id}`,
    `tab=${tab}`,
    `sim=${sim}`,
    `running=${state.running ? 'yes' : 'no'}`,
    `cycle=${state.cycle}`,
    `trace=${trace}`,
    `watches=${state.watches.size}`,
    `breakpoints=${state.breakpoints.length}`
  ].join(' ');
}

function terminalHelpText() {
  return [
    'Commands:',
    '  help',
    '  status',
    '  config <show|hide|toggle>',
    '  terminal <show|hide|toggle|clear>',
    '  tab <io|vcd|memory|components|schematic>',
    '  runner <generic|cpu|apple2> [load]',
    '  backend <interpreter|jit|compiler>',
    '  theme <shenzhen|original>',
    '  init | reset | step [n] | run | pause',
    '  clock <signal|none>',
    '  batch <n> | ui_every <n>',
    '  trace <start|stop|clear|save>',
    '  watch <add NAME|remove NAME|clear|list>',
    '  bp <add NAME VALUE|remove NAME|clear|list>',
    '  io <hires|color|sound> <on|off|toggle>',
    '  key <char|enter|backspace>',
    '  memory view [start] [len]',
    '  memory followpc <on|off|toggle>',
    '  memory write <addr> <value>',
    '  memory reset [vector]',
    '  memory <karateka|load_last|save_dump|save_snapshot|load_selected>',
    '  sample [path]  (generic runner)',
    '  set <elementId> <value>  (generic UI setter)',
    '  click <elementId>        (generic UI button click)'
  ].join('\n');
}

function clearAllWatches() {
  state.watches.clear();
  refreshWatchTable();
  renderWatchList();
}

function addBreakpointSignal(signal, valueRaw) {
  if (!state.sim) {
    throw new Error('Simulator not initialized.');
  }
  const parsed = parseNumeric(valueRaw);
  if (parsed == null) {
    throw new Error(`Invalid breakpoint value: ${valueRaw}`);
  }

  let idx = null;
  if (state.sim.features.hasSignalIndex) {
    const resolved = state.sim.get_signal_idx(signal);
    if (resolved < 0) {
      throw new Error(`Unknown signal: ${signal}`);
    }
    idx = resolved;
  } else if (!state.sim.has_signal(signal)) {
    throw new Error(`Unknown signal: ${signal}`);
  }

  const width = state.irMeta?.widths.get(signal) || 1;
  const mask = maskForWidth(width);
  const value = parsed & mask;
  state.breakpoints = state.breakpoints.filter((bp) => bp.name !== signal);
  state.breakpoints.push({ name: signal, idx, width, value });
  renderBreakpointList();
  return value;
}

function clearAllBreakpoints() {
  state.breakpoints = [];
  renderBreakpointList();
}

async function executeTerminalCommand(rawLine) {
  const tokens = tokenizeCommandLine(rawLine);
  if (tokens.length === 0) {
    return null;
  }
  const cmd = tokens.shift().toLowerCase();

  if (cmd === 'help' || cmd === '?') {
    return terminalHelpText();
  }
  if (cmd === 'status') {
    return terminalStatusText();
  }
  if (cmd === 'clear') {
    terminalClear();
    return null;
  }

  if (cmd === 'config') {
    const mode = String(tokens[0] || 'toggle').toLowerCase();
    if (mode === 'toggle') {
      setSidebarCollapsed(!state.sidebarCollapsed);
    } else {
      const desired = parseBooleanToken(mode);
      if (desired == null) {
        throw new Error('Usage: config <show|hide|toggle>');
      }
      setSidebarCollapsed(!desired);
    }
    return `config ${state.sidebarCollapsed ? 'hidden' : 'visible'}`;
  }

  if (cmd === 'terminal') {
    const mode = String(tokens[0] || 'toggle').toLowerCase();
    if (mode === 'clear') {
      terminalClear();
      return null;
    }
    if (mode === 'toggle') {
      setTerminalOpen(!state.terminalOpen, { focus: true });
    } else {
      const desired = parseBooleanToken(mode);
      if (desired == null) {
        throw new Error('Usage: terminal <show|hide|toggle|clear>');
      }
      setTerminalOpen(desired, { focus: desired });
    }
    return `terminal ${state.terminalOpen ? 'open' : 'closed'}`;
  }

  if (cmd === 'tab') {
    const tabId = parseTabToken(tokens[0]);
    if (!tabId) {
      throw new Error('Usage: tab <io|vcd|memory|components|schematic>');
    }
    setActiveTab(tabId);
    return `tab=${tabId}`;
  }

  if (cmd === 'runner') {
    const runnerId = parseRunnerToken(tokens[0]);
    if (!runnerId) {
      throw new Error('Usage: runner <generic|cpu|apple2> [load]');
    }
    state.runnerPreset = runnerId;
    if (dom.runnerSelect) {
      dom.runnerSelect.value = runnerId;
    }
    updateIrSourceVisibility();
    const doLoad = tokens.length < 2 || String(tokens[1] || '').toLowerCase() !== 'select';
    if (doLoad) {
      await loadRunnerPreset();
      return `runner loaded: ${runnerId}`;
    }
    refreshStatus();
    return `runner selected: ${runnerId}`;
  }

  if (cmd === 'backend') {
    const backendId = parseBackendToken(tokens[0]);
    if (!backendId) {
      throw new Error('Usage: backend <interpreter|jit|compiler>');
    }
    if (dom.backendSelect) {
      dom.backendSelect.value = backendId;
      dom.backendSelect.dispatchEvent(new Event('change', { bubbles: true }));
    }
    return `backend change requested: ${backendId}`;
  }

  if (cmd === 'theme') {
    const theme = String(tokens[0] || '').toLowerCase();
    if (!['shenzhen', 'original'].includes(theme)) {
      throw new Error('Usage: theme <shenzhen|original>');
    }
    applyTheme(theme);
    return `theme=${theme}`;
  }

  if (cmd === 'sample') {
    if (!currentRunnerPreset().usesManualIr) {
      throw new Error('Sample command is only available on the generic runner.');
    }
    if (tokens[0]) {
      if (!dom.sampleSelect) {
        throw new Error('Sample selector unavailable.');
      }
      const samplePath = tokens[0];
      const exists = Array.from(dom.sampleSelect.options).some((opt) => opt.value === samplePath);
      if (!exists) {
        throw new Error(`Unknown sample: ${samplePath}`);
      }
      dom.sampleSelect.value = samplePath;
    }
    await loadSample();
    return `sample loaded: ${dom.sampleSelect?.value || ''}`;
  }

  if (cmd === 'init') {
    await initializeSimulator();
    return 'simulator initialized';
  }
  if (cmd === 'reset') {
    dom.resetBtn?.click();
    return 'simulator reset';
  }
  if (cmd === 'step') {
    if (tokens[0]) {
      setUiInputValueById('stepTicks', tokens[0]);
    }
    stepSimulation();
    return `stepped ${dom.stepTicks?.value || '1'} tick(s)`;
  }
  if (cmd === 'run') {
    dom.runBtn?.click();
    return 'run started';
  }
  if (cmd === 'pause') {
    dom.pauseBtn?.click();
    return 'run paused';
  }
  if (cmd === 'clock') {
    const value = String(tokens[0] || '').trim();
    if (!value) {
      throw new Error('Usage: clock <signal|none>');
    }
    const next = value.toLowerCase() === 'none' ? '__none__' : value;
    if (!dom.clockSignal) {
      throw new Error('Clock selector unavailable.');
    }
    const hasOption = Array.from(dom.clockSignal.options).some((opt) => opt.value === next);
    if (!hasOption) {
      throw new Error(`Unknown clock signal: ${next}`);
    }
    dom.clockSignal.value = next;
    dom.clockSignal.dispatchEvent(new Event('change', { bubbles: true }));
    return `clock=${next === '__none__' ? '(none)' : next}`;
  }
  if (cmd === 'batch') {
    if (!tokens[0]) {
      throw new Error('Usage: batch <n>');
    }
    return setUiInputValueById('runBatch', tokens[0]);
  }
  if (cmd === 'ui_every' || cmd === 'ui-every' || cmd === 'uievery') {
    if (!tokens[0]) {
      throw new Error('Usage: ui_every <n>');
    }
    return setUiInputValueById('uiUpdateCycles', tokens[0]);
  }

  if (cmd === 'trace') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'start') {
      dom.traceStartBtn?.click();
      return 'trace started';
    }
    if (sub === 'stop') {
      dom.traceStopBtn?.click();
      return 'trace stopped';
    }
    if (sub === 'clear') {
      dom.traceClearBtn?.click();
      return 'trace cleared';
    }
    if (sub === 'save') {
      dom.downloadVcdBtn?.click();
      return 'trace save started';
    }
    throw new Error('Usage: trace <start|stop|clear|save>');
  }

  if (cmd === 'watch') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'add') {
      const signal = String(tokens[1] || '').trim();
      if (!signal) {
        throw new Error('Usage: watch add <signal>');
      }
      const ok = addWatchSignal(signal);
      if (!ok) {
        throw new Error(`Could not add watch: ${signal}`);
      }
      return `watch added: ${signal}`;
    }
    if (sub === 'remove' || sub === 'rm' || sub === 'del') {
      const signal = String(tokens[1] || '').trim();
      if (!signal) {
        throw new Error('Usage: watch remove <signal>');
      }
      const ok = removeWatchSignal(signal);
      if (!ok) {
        throw new Error(`Watch not found: ${signal}`);
      }
      return `watch removed: ${signal}`;
    }
    if (sub === 'clear') {
      clearAllWatches();
      return 'watches cleared';
    }
    if (sub === 'list') {
      const names = Array.from(state.watches.keys());
      return names.length > 0 ? names.join('\n') : '(no watches)';
    }
    throw new Error('Usage: watch <add|remove|clear|list> ...');
  }

  if (cmd === 'bp' || cmd === 'breakpoint') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'add') {
      const signal = String(tokens[1] || '').trim();
      const valueRaw = String(tokens[2] || '').trim();
      if (!signal || !valueRaw) {
        throw new Error('Usage: bp add <signal> <value>');
      }
      const value = addBreakpointSignal(signal, valueRaw);
      return `breakpoint added: ${signal}=${formatValue(value, 64)}`;
    }
    if (sub === 'remove' || sub === 'rm' || sub === 'del') {
      const signal = String(tokens[1] || '').trim();
      if (!signal) {
        throw new Error('Usage: bp remove <signal>');
      }
      state.breakpoints = state.breakpoints.filter((bp) => bp.name !== signal);
      renderBreakpointList();
      return `breakpoint removed: ${signal}`;
    }
    if (sub === 'clear') {
      clearAllBreakpoints();
      return 'breakpoints cleared';
    }
    if (sub === 'list') {
      return state.breakpoints.length > 0
        ? state.breakpoints.map((bp) => `${bp.name}=${formatValue(bp.value, bp.width)}`).join('\n')
        : '(no breakpoints)';
    }
    throw new Error('Usage: bp <add|remove|clear|list> ...');
  }

  if (cmd === 'io') {
    const field = String(tokens[0] || '').toLowerCase();
    const action = String(tokens[1] || '').toLowerCase();
    const targetMap = {
      hires: dom.toggleHires,
      color: dom.toggleColor,
      sound: dom.toggleSound
    };
    const target = targetMap[field];
    if (!(target instanceof HTMLInputElement)) {
      throw new Error('Usage: io <hires|color|sound> <on|off|toggle>');
    }
    if (action === 'toggle') {
      target.checked = !target.checked;
    } else {
      const parsed = parseBooleanToken(action);
      if (parsed == null) {
        throw new Error('Usage: io <hires|color|sound> <on|off|toggle>');
      }
      target.checked = parsed;
    }
    target.dispatchEvent(new Event('change', { bubbles: true }));
    return `${field}=${target.checked ? 'on' : 'off'}`;
  }

  if (cmd === 'key') {
    const raw = String(tokens[0] || '').toLowerCase();
    if (!raw) {
      throw new Error('Usage: key <char|enter|backspace>');
    }
    if (raw === 'enter') {
      queueApple2Key('\r');
      return 'key queued: ENTER';
    }
    if (raw === 'backspace') {
      queueApple2Key(String.fromCharCode(0x08));
      return 'key queued: BACKSPACE';
    }
    queueApple2Key(tokens[0][0]);
    return `key queued: ${tokens[0][0]}`;
  }

  if (cmd === 'memory') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'view') {
      if (tokens[1]) {
        setUiInputValueById('memoryStart', tokens[1]);
      }
      if (tokens[2]) {
        setUiInputValueById('memoryLength', tokens[2]);
      }
      refreshMemoryView();
      return `memory view start=${dom.memoryStart?.value || ''} len=${dom.memoryLength?.value || ''}`;
    }
    if (sub === 'followpc' || sub === 'follow_pc') {
      const action = String(tokens[1] || '').toLowerCase();
      if (action === 'toggle') {
        state.memory.followPc = !state.memory.followPc;
      } else {
        const parsed = parseBooleanToken(action);
        if (parsed == null) {
          throw new Error('Usage: memory followpc <on|off|toggle>');
        }
        state.memory.followPc = parsed;
      }
      if (dom.memoryFollowPc) {
        dom.memoryFollowPc.checked = state.memory.followPc;
      }
      refreshMemoryView();
      return `memory.followPc=${state.memory.followPc ? 'on' : 'off'}`;
    }
    if (sub === 'write') {
      const addr = tokens[1];
      const value = tokens[2];
      if (!addr || !value) {
        throw new Error('Usage: memory write <addr> <value>');
      }
      setUiInputValueById('memoryWriteAddr', addr);
      setUiInputValueById('memoryWriteValue', value);
      dom.memoryWriteBtn?.click();
      return `memory write requested @${addr}=${value}`;
    }
    if (sub === 'reset') {
      if (tokens[1]) {
        setUiInputValueById('memoryResetVector', tokens[1]);
      }
      await resetApple2WithMemoryVectorOverride();
      return `memory reset vector applied (${dom.memoryResetVector?.value || 'ROM'})`;
    }
    if (sub === 'karateka') {
      await loadKaratekaDump();
      return 'karateka dump load requested';
    }
    if (sub === 'load_last' || sub === 'load-last') {
      await loadLastSavedApple2Dump();
      return 'load last dump requested';
    }
    if (sub === 'save_dump' || sub === 'save-dump') {
      await saveApple2MemoryDump();
      return 'save dump requested';
    }
    if (sub === 'save_snapshot' || sub === 'save-snapshot') {
      await saveApple2MemorySnapshot();
      return 'save snapshot requested';
    }
    if (sub === 'load_selected' || sub === 'load-selected') {
      dom.memoryDumpLoadBtn?.click();
      return 'load selected dump requested';
    }
    throw new Error('Usage: memory <view|followpc|write|reset|karateka|load_last|save_dump|save_snapshot|load_selected> ...');
  }

  if (cmd === 'set') {
    const id = tokens.shift();
    if (!id || tokens.length === 0) {
      throw new Error('Usage: set <elementId> <value>');
    }
    return setUiInputValueById(id, tokens.join(' '));
  }

  if (cmd === 'click') {
    const id = tokens[0];
    if (!id) {
      throw new Error('Usage: click <elementId>');
    }
    return clickUiElementById(id);
  }

  throw new Error(`Unknown command: ${cmd}. Use "help".`);
}

async function runTerminalCommand(rawLine) {
  const line = String(rawLine || '').trim();
  if (!line) {
    return;
  }
  terminalWriteLine(`$ ${line}`);
  const result = await executeTerminalCommand(line);
  if (result) {
    terminalWriteLine(result);
  }
}

async function submitTerminalInput() {
  const line = String(dom.terminalInput?.value || '').trim();
  if (!line) {
    return;
  }
  if (state.terminal.busy) {
    terminalWriteLine('busy: previous command still running');
    return;
  }
  if (line && (state.terminal.history.length === 0 || state.terminal.history[state.terminal.history.length - 1] !== line)) {
    state.terminal.history.push(line);
  }
  state.terminal.historyIndex = state.terminal.history.length;
  if (dom.terminalInput) {
    dom.terminalInput.value = '';
  }
  state.terminal.busy = true;
  try {
    await runTerminalCommand(line);
  } catch (err) {
    terminalWriteLine(`error: ${err.message || err}`);
  } finally {
    state.terminal.busy = false;
    refreshStatus();
  }
}

function terminalHistoryNavigate(delta) {
  const history = state.terminal.history;
  if (!dom.terminalInput || history.length === 0) {
    return;
  }
  const maxIndex = history.length;
  let next = state.terminal.historyIndex + delta;
  next = Math.max(0, Math.min(maxIndex, next));
  state.terminal.historyIndex = next;
  if (next >= history.length) {
    dom.terminalInput.value = '';
    return;
  }
  dom.terminalInput.value = history[next];
  requestAnimationFrame(() => {
    dom.terminalInput.selectionStart = dom.terminalInput.value.length;
    dom.terminalInput.selectionEnd = dom.terminalInput.value.length;
  });
}

function parseIrMeta(irJson) {
  const ir = JSON.parse(irJson);
  const widths = new Map();
  const signalInfo = new Map();
  const names = [];

  for (const kind of ['ports', 'nets', 'regs']) {
    const entries = Array.isArray(ir[kind]) ? ir[kind] : [];
    for (const entry of entries) {
      if (!entry || typeof entry.name !== 'string') {
        continue;
      }
      if (!widths.has(entry.name)) {
        names.push(entry.name);
      }
      const width = Number.parseInt(entry.width, 10) || 1;
      widths.set(entry.name, width);
      signalInfo.set(entry.name, {
        name: entry.name,
        width,
        kind,
        direction: entry.direction || null,
        entry
      });
    }
  }

  const clocks = [];
  const processes = Array.isArray(ir.processes) ? ir.processes : [];
  for (const process of processes) {
    if (process?.clocked && typeof process.clock === 'string' && !clocks.includes(process.clock)) {
      clocks.push(process.clock);
    }
  }

  const clockSet = new Set(clocks);
  for (const name of names) {
    if (/(\bclock\b|(^|[_./])clk([_./]|$))/i.test(name)) {
      clockSet.add(name);
    }
  }

  for (const preferred of ['clk', 'clock']) {
    if (widths.has(preferred)) {
      clockSet.add(preferred);
    }
  }

  const rankClock = (name) => {
    if (/^(clk|clock)$/i.test(name)) {
      return 0;
    }
    if (!name.includes('__')) {
      return 1;
    }
    if (/__clk$/i.test(name)) {
      return 2;
    }
    return 3;
  };

  const clockCandidates = Array.from(clockSet).sort((a, b) => {
    const rankDiff = rankClock(a) - rankClock(b);
    if (rankDiff !== 0) {
      return rankDiff;
    }
    return a.localeCompare(b);
  });

  return { ir, widths, signalInfo, names, clocks, clockCandidates };
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
  state.components.overrideSource = String(source || '');
  state.components.overrideMeta = meta || null;
}

function clearComponentSourceOverride() {
  setComponentSourceOverride('', null);
}

function resetComponentExplorerState() {
  state.components.model = null;
  state.components.selectedNodeId = null;
  state.components.parseError = '';
  state.components.sourceKey = '';
  state.components.graphFocusId = null;
  state.components.graphShowChildren = false;
  state.components.graphLastTap = null;
  state.components.graphHighlightedSignal = null;
  state.components.graphLiveValues = new Map();
  state.components.graphLayoutEngine = 'none';
  clearComponentSourceBundle();
  clearComponentSchematicBundle();
  destroyComponentGraph();
}

function currentComponentSourceText() {
  if (state.components.overrideSource) {
    return state.components.overrideSource;
  }
  return dom.irJson?.value || '';
}

function updateIrSourceVisibility() {
  const preset = currentRunnerPreset();
  const show = !!preset.usesManualIr;
  if (dom.irSourceSection) {
    dom.irSourceSection.hidden = !show;
  }
}

async function fetchTextAsset(path, label = 'asset') {
  const response = await fetch(path);
  if (!response.ok) {
    throw new Error(`${label} load failed (${response.status})`);
  }
  return response.text();
}

async function fetchJsonAsset(path, label = 'asset') {
  const text = await fetchTextAsset(path, label);
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`${label} parse failed: ${err.message || err}`);
  }
}

function normalizeComponentSourceBundle(raw) {
  if (!raw || typeof raw !== 'object') {
    return null;
  }

  const components = Array.isArray(raw.components) ? raw.components : [];
  const byClass = new Map();
  const byModule = new Map();
  for (const entry of components) {
    if (!entry || typeof entry !== 'object') {
      continue;
    }
    const className = String(entry.component_class || '').trim();
    const moduleName = String(entry.module_name || '').trim();
    if (className) {
      byClass.set(className, entry);
    }
    if (moduleName) {
      byModule.set(moduleName, entry);
      byModule.set(moduleName.toLowerCase(), entry);
    }
  }

  let topEntry = null;
  const topClass = String(raw.top_component_class || '').trim();
  if (topClass && byClass.has(topClass)) {
    topEntry = byClass.get(topClass);
  } else if (raw.top && typeof raw.top === 'object') {
    topEntry = raw.top;
  } else if (components.length > 0) {
    topEntry = components[0];
  }

  return {
    ...raw,
    components,
    byClass,
    byModule,
    top: topEntry
  };
}

function clearComponentSourceBundle() {
  state.components.sourceBundle = null;
  state.components.sourceBundleByClass = new Map();
  state.components.sourceBundleByModule = new Map();
}

function setComponentSourceBundle(bundle) {
  const normalized = normalizeComponentSourceBundle(bundle);
  if (!normalized) {
    clearComponentSourceBundle();
    return;
  }
  state.components.sourceBundle = normalized;
  state.components.sourceBundleByClass = normalized.byClass || new Map();
  state.components.sourceBundleByModule = normalized.byModule || new Map();
}

function normalizeComponentSchematicBundle(raw) {
  if (!raw || typeof raw !== 'object') {
    return null;
  }
  const components = Array.isArray(raw.components) ? raw.components : [];
  const byPath = new Map();
  for (const entry of components) {
    if (!entry || typeof entry !== 'object') {
      continue;
    }
    const path = String(entry.path || '').trim();
    if (!path) {
      continue;
    }
    byPath.set(path, entry);
  }
  return {
    ...raw,
    components,
    byPath
  };
}

function clearComponentSchematicBundle() {
  state.components.schematicBundle = null;
  state.components.schematicBundleByPath = new Map();
}

function setComponentSchematicBundle(bundle) {
  const normalized = normalizeComponentSchematicBundle(bundle);
  if (!normalized) {
    clearComponentSchematicBundle();
    return;
  }
  state.components.schematicBundle = normalized;
  state.components.schematicBundleByPath = normalized.byPath || new Map();
}

function normalizeComponentCodeView(view) {
  return view === 'verilog' ? 'verilog' : 'rhdl';
}

function renderComponentCodeViewButtons() {
  const view = normalizeComponentCodeView(state.components.codeView);
  if (dom.componentCodeViewRhdl) {
    dom.componentCodeViewRhdl.classList.toggle('active', view === 'rhdl');
  }
  if (dom.componentCodeViewVerilog) {
    dom.componentCodeViewVerilog.classList.toggle('active', view === 'verilog');
  }
}

function setComponentCodeView(view) {
  const next = normalizeComponentCodeView(view);
  if (state.components.codeView !== next) {
    state.components.codeView = next;
    renderComponentInspector();
  }
  renderComponentCodeViewButtons();
}

async function loadRunnerIrBundle(preset, options = {}) {
  const { logLoad = false } = options;
  if (!preset || preset.usesManualIr) {
    return {
      simJson: String(dom.irJson?.value || '').trim(),
      explorerJson: String(dom.irJson?.value || '').trim(),
      explorerMeta: null,
      sourceBundle: null,
      schematicBundle: null
    };
  }

  const simJson = (await fetchTextAsset(preset.simIrPath, `${preset.label} IR`)).trim();
  let explorerJson = simJson;
  if (preset.explorerIrPath && preset.explorerIrPath !== preset.simIrPath) {
    explorerJson = (await fetchTextAsset(preset.explorerIrPath, `${preset.label} hierarchical IR`)).trim();
  }

  if (dom.irJson) {
    dom.irJson.value = simJson;
  }
  resetComponentExplorerState();

  let explorerMeta = null;
  if (explorerJson) {
    explorerMeta = parseIrMeta(explorerJson);
  }

  let sourceBundle = null;
  if (preset.sourceBundlePath) {
    try {
      const rawBundle = await fetchJsonAsset(preset.sourceBundlePath, `${preset.label} source bundle`);
      sourceBundle = normalizeComponentSourceBundle(rawBundle);
    } catch (err) {
      log(`Source bundle load failed for ${preset.label}: ${err.message || err}`);
    }
  }

  let schematicBundle = null;
  if (preset.schematicPath) {
    try {
      const rawSchematic = await fetchJsonAsset(preset.schematicPath, `${preset.label} schematic`);
      schematicBundle = normalizeComponentSchematicBundle(rawSchematic);
    } catch (err) {
      log(`Schematic load failed for ${preset.label}: ${err.message || err}`);
    }
  }

  if (logLoad) {
    log(`Loaded ${preset.label} IR bundle`);
  }
  return {
    simJson,
    explorerJson,
    explorerMeta,
    sourceBundle,
    schematicBundle
  };
}

function setActiveTab(tabId) {
  state.activeTab = tabId;
  for (const btn of dom.tabButtons) {
    const selected = btn.dataset.tab === tabId;
    btn.classList.toggle('active', selected);
    btn.setAttribute('aria-selected', selected ? 'true' : 'false');
  }
  for (const panel of dom.tabPanels) {
    panel.classList.toggle('active', panel.id === tabId);
  }
  requestAnimationFrame(() => {
    refreshAllDashboardRowSizing();
  });

  if (tabId === 'vcdTab') {
    requestAnimationFrame(() => {
      window.dispatchEvent(new Event('resize'));
    });
  }
  if (tabId === 'componentTab' || tabId === 'componentGraphTab') {
    refreshComponentExplorer();
  }
}

function currentIrSourceKey(irText) {
  const source = String(irText || '');
  if (!source) {
    return '';
  }
  const first = source.charCodeAt(0) || 0;
  const last = source.charCodeAt(source.length - 1) || 0;
  return `${source.length}:${first}:${last}`;
}

function setSidebarCollapsed(collapsed) {
  state.sidebarCollapsed = !!collapsed;
  if (dom.appShell) {
    dom.appShell.classList.toggle('controls-collapsed', state.sidebarCollapsed);
  }
  if (dom.sidebarToggleBtn) {
    dom.sidebarToggleBtn.setAttribute('aria-expanded', state.sidebarCollapsed ? 'false' : 'true');
    dom.sidebarToggleBtn.setAttribute('aria-label', state.sidebarCollapsed ? 'Show Config' : 'Hide Config');
    dom.sidebarToggleBtn.setAttribute('title', state.sidebarCollapsed ? 'Show Config' : 'Hide Config');
    dom.sidebarToggleBtn.classList.toggle('is-active', !state.sidebarCollapsed);
  }
  try {
    localStorage.setItem(SIDEBAR_COLLAPSED_KEY, state.sidebarCollapsed ? '1' : '0');
  } catch (_err) {
    // Ignore storage failures (private mode, policy, etc).
  }
  requestAnimationFrame(() => {
    refreshAllDashboardRowSizing();
  });
}

function setTerminalOpen(open, { persist = true, focus = false } = {}) {
  state.terminalOpen = !!open;
  if (dom.terminalPanel) {
    dom.terminalPanel.hidden = !state.terminalOpen;
  }
  if (dom.terminalToggleBtn) {
    dom.terminalToggleBtn.classList.toggle('is-active', state.terminalOpen);
    dom.terminalToggleBtn.setAttribute('aria-expanded', state.terminalOpen ? 'true' : 'false');
    dom.terminalToggleBtn.setAttribute('aria-label', state.terminalOpen ? 'Hide Terminal' : 'Show Terminal');
    dom.terminalToggleBtn.setAttribute('title', state.terminalOpen ? 'Hide Terminal' : 'Show Terminal');
  }
  if (persist) {
    try {
      localStorage.setItem(TERMINAL_OPEN_KEY, state.terminalOpen ? '1' : '0');
    } catch (_err) {
      // Ignore storage failures.
    }
  }
  requestAnimationFrame(() => {
    refreshAllDashboardRowSizing();
  });
  if (state.terminalOpen && focus && dom.terminalInput) {
    requestAnimationFrame(() => {
      dom.terminalInput.focus();
      dom.terminalInput.select();
    });
  }
}

function setPanelCollapsed(panel, button, collapsed) {
  const next = !!collapsed;
  panel.classList.toggle('is-collapsed', next);
  button.textContent = '';
  button.classList.toggle('is-collapsed', next);
  button.setAttribute('aria-expanded', next ? 'false' : 'true');
  button.setAttribute('title', next ? 'Expand' : 'Collapse');
  const title = String(panel.dataset.collapseTitle || 'panel');
  button.setAttribute('aria-label', `${next ? 'Expand' : 'Collapse'} ${title}`);
}

function handlePanelCollapseChanged(panel, collapsed) {
  const rootKey = String(panel?.dataset?.layoutRootKey || '').trim();
  requestAnimationFrame(() => {
    if (rootKey) {
      refreshDashboardRowSizing(rootKey);
    } else {
      refreshAllDashboardRowSizing();
    }
  });

  if (collapsed) {
    return;
  }

  if (
    panel.classList.contains('component-tree-panel')
    || panel.classList.contains('component-signal-panel')
    || panel.classList.contains('component-detail-panel')
    || panel.classList.contains('component-visual-panel')
    || panel.classList.contains('component-live-panel')
    || panel.classList.contains('component-connection-panel')
  ) {
    requestAnimationFrame(() => {
      if (isComponentTabActive()) {
        refreshActiveComponentTab();
      }
    });
    return;
  }

  if (state.activeTab === 'vcdTab') {
    requestAnimationFrame(() => {
      window.dispatchEvent(new Event('resize'));
    });
    return;
  }

  if (state.activeTab === 'memoryTab') {
    requestAnimationFrame(() => {
      refreshMemoryView();
    });
  }
}

function initializeCollapsiblePanels() {
  const panels = Array.from(document.querySelectorAll(COLLAPSIBLE_PANEL_SELECTOR));
  for (const panel of panels) {
    if (!(panel instanceof HTMLElement) || panel.dataset.collapseReady === '1') {
      continue;
    }

    const heading = panel.querySelector(':scope > h1, :scope > h2, :scope > h3, :scope > h4, :scope > h5, :scope > h6');
    if (!(heading instanceof HTMLElement)) {
      continue;
    }

    panel.classList.add('collapsible-panel');
    panel.dataset.collapseReady = '1';
    panel.dataset.collapseTitle = String(heading.textContent || '').trim().replace(/\s+/g, ' ') || 'panel';

    heading.classList.add('panel-header-title');

    const headerRow = document.createElement('div');
    headerRow.className = 'panel-header-row';
    panel.insertBefore(headerRow, panel.firstChild);
    headerRow.appendChild(heading);

    const collapseBtn = document.createElement('button');
    collapseBtn.type = 'button';
    collapseBtn.className = 'panel-collapse-btn';
    headerRow.appendChild(collapseBtn);
    setPanelCollapsed(panel, collapseBtn, false);

    collapseBtn.addEventListener('click', () => {
      const nextCollapsed = !panel.classList.contains('is-collapsed');
      setPanelCollapsed(panel, collapseBtn, nextCollapsed);
      handlePanelCollapseChanged(panel, nextCollapsed);
    });
  }
}

function safeSlugToken(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    || 'panel';
}

function readDashboardLayouts() {
  try {
    const raw = localStorage.getItem(DASHBOARD_LAYOUT_KEY);
    if (!raw) {
      return {};
    }
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return {};
    }
    return parsed;
  } catch (_err) {
    return {};
  }
}

function writeDashboardLayouts() {
  try {
    localStorage.setItem(DASHBOARD_LAYOUT_KEY, JSON.stringify(state.dashboard.layouts || {}));
  } catch (_err) {
    // Ignore storage failures.
  }
}

function dashboardRootPanels(root) {
  return Array.from(root.children).filter((child) => child instanceof HTMLElement && child.classList.contains('dashboard-panel'));
}

function normalizeDashboardSpan(value, fallback = 'full') {
  if (value === 'half') {
    return 'half';
  }
  if (value === 'full') {
    return 'full';
  }
  return fallback === 'half' ? 'half' : 'full';
}

function panelHeaderTitle(panel) {
  const raw = String(panel.dataset.collapseTitle || '').trim();
  if (raw) {
    return raw;
  }
  const heading = panel.querySelector(':scope > .panel-header-row > .panel-header-title, :scope > h1, :scope > h2, :scope > h3');
  return String(heading?.textContent || '').trim() || 'Panel';
}

function defaultDashboardSpan(rootKey, panel) {
  void rootKey;
  void panel;
  return 'full';
}

function normalizeDashboardSpansForRoot(root) {
  if (!(root instanceof HTMLElement)) {
    return;
  }
  const panels = dashboardRootPanels(root);
  let pendingHalf = null;
  for (const panel of panels) {
    const span = normalizeDashboardSpan(panel.dataset.layoutSpan, 'full');
    panel.dataset.layoutSpan = span;
    if (span === 'full') {
      if (pendingHalf) {
        pendingHalf.dataset.layoutSpan = 'full';
        pendingHalf = null;
      }
      continue;
    }
    if (!pendingHalf) {
      pendingHalf = panel;
      continue;
    }
    pendingHalf = null;
  }
  if (pendingHalf) {
    pendingHalf.dataset.layoutSpan = 'full';
  }
}

function dashboardRowsForRoot(root) {
  const panels = dashboardRootPanels(root);
  const rows = [];
  let idx = 0;
  while (idx < panels.length) {
    const first = panels[idx];
    const firstSpan = normalizeDashboardSpan(first.dataset.layoutSpan, 'full');
    if (firstSpan === 'half') {
      const second = panels[idx + 1];
      if (second && normalizeDashboardSpan(second.dataset.layoutSpan, 'full') === 'half') {
        rows.push([first, second]);
        idx += 2;
        continue;
      }
      first.dataset.layoutSpan = 'full';
      rows.push([first]);
      idx += 1;
      continue;
    }
    rows.push([first]);
    idx += 1;
  }
  return rows;
}

function dashboardRowSignature(rowPanels) {
  return rowPanels
    .map((panel) => String(panel?.dataset?.layoutItemId || '').trim())
    .filter(Boolean)
    .join('|');
}

function dashboardLayoutRowHeights(rootKey) {
  const layout = state.dashboard.layouts?.[rootKey];
  if (!layout || typeof layout !== 'object') {
    return {};
  }
  if (!layout.rowHeights || typeof layout.rowHeights !== 'object') {
    return {};
  }
  return layout.rowHeights;
}

function clearDashboardRowSizing(root) {
  if (!(root instanceof HTMLElement)) {
    return;
  }
  const handles = Array.from(root.querySelectorAll(':scope > .dashboard-row-resize-handle'));
  for (const handle of handles) {
    handle.remove();
  }
  for (const panel of dashboardRootPanels(root)) {
    panel.classList.remove('dashboard-row-sized');
    panel.style.removeProperty('--dashboard-row-height');
  }
}

function isDashboardRootVisible(rootKey, root) {
  if (!(root instanceof HTMLElement)) {
    return false;
  }
  if (rootKey === 'controls') {
    return !state.sidebarCollapsed && root.offsetParent !== null;
  }
  const tabPanel = root.classList.contains('tab-panel') ? root : root.closest('.tab-panel');
  if (!(tabPanel instanceof HTMLElement)) {
    return root.offsetParent !== null;
  }
  return tabPanel.classList.contains('active');
}

function refreshDashboardRowSizing(rootKey) {
  const root = state.dashboard.rootElements.get(rootKey);
  if (!(root instanceof HTMLElement)) {
    return;
  }

  normalizeDashboardSpansForRoot(root);
  clearDashboardRowSizing(root);

  const rows = dashboardRowsForRoot(root);
  const rowHeights = dashboardLayoutRowHeights(rootKey);
  for (const rowPanels of rows) {
    const signature = dashboardRowSignature(rowPanels);
    if (!signature) {
      continue;
    }
    const savedHeight = Number(rowHeights[signature]);
    if (!Number.isFinite(savedHeight) || savedHeight < DASHBOARD_MIN_ROW_HEIGHT) {
      continue;
    }
    for (const panel of rowPanels) {
      panel.classList.add('dashboard-row-sized');
      panel.style.setProperty('--dashboard-row-height', `${Math.round(savedHeight)}px`);
    }
  }

  if (!isDashboardRootVisible(rootKey, root)) {
    return;
  }

  const rootRect = root.getBoundingClientRect();
  if (!(rootRect.width > 0 && rootRect.height > 0)) {
    return;
  }

  for (const rowPanels of rows) {
    const signature = dashboardRowSignature(rowPanels);
    if (!signature) {
      continue;
    }
    let minLeft = Infinity;
    let maxRight = -Infinity;
    let maxBottom = -Infinity;
    for (const panel of rowPanels) {
      const rect = panel.getBoundingClientRect();
      if (!(rect.width > 0 && rect.height > 0)) {
        continue;
      }
      minLeft = Math.min(minLeft, rect.left);
      maxRight = Math.max(maxRight, rect.right);
      maxBottom = Math.max(maxBottom, rect.bottom);
    }
    if (!Number.isFinite(minLeft) || !Number.isFinite(maxRight) || !Number.isFinite(maxBottom)) {
      continue;
    }

    const handle = document.createElement('div');
    handle.className = 'dashboard-row-resize-handle';
    handle.dataset.rootKey = rootKey;
    handle.dataset.rowSignature = signature;
    handle.style.left = `${Math.max(0, minLeft - rootRect.left + root.scrollLeft)}px`;
    handle.style.width = `${Math.max(0, maxRight - minLeft)}px`;
    handle.style.top = `${Math.max(0, maxBottom - rootRect.top + root.scrollTop - 4)}px`;
    handle.title = 'Drag to resize row';
    root.appendChild(handle);
  }
}

function refreshAllDashboardRowSizing() {
  for (const rootKey of state.dashboard.rootElements.keys()) {
    refreshDashboardRowSizing(rootKey);
  }
}

function setDashboardRowHeight(rootKey, signature, heightPx) {
  if (!rootKey || !signature) {
    return;
  }
  const height = Math.max(DASHBOARD_MIN_ROW_HEIGHT, Math.round(heightPx));
  const existing = state.dashboard.layouts[rootKey] && typeof state.dashboard.layouts[rootKey] === 'object'
    ? state.dashboard.layouts[rootKey]
    : {};
  const rowHeights = existing.rowHeights && typeof existing.rowHeights === 'object'
    ? { ...existing.rowHeights }
    : {};
  rowHeights[signature] = height;
  state.dashboard.layouts[rootKey] = {
    ...existing,
    rowHeights
  };
  writeDashboardLayouts();
  refreshDashboardRowSizing(rootKey);
  notifyDashboardLayoutChanged(rootKey);
}

function handleDashboardResizeMouseMove(event) {
  if (!state.dashboard.resizing.active) {
    return;
  }
  const rootKey = state.dashboard.resizing.rootKey;
  const root = state.dashboard.rootElements.get(rootKey);
  if (!(root instanceof HTMLElement)) {
    return;
  }
  const rows = dashboardRowsForRoot(root);
  const signature = state.dashboard.resizing.rowSignature;
  const rowPanels = rows.find((row) => dashboardRowSignature(row) === signature);
  if (!rowPanels || rowPanels.length === 0) {
    return;
  }

  const delta = event.clientY - state.dashboard.resizing.startY;
  const nextHeight = Math.max(DASHBOARD_MIN_ROW_HEIGHT, state.dashboard.resizing.startHeight + delta);
  for (const panel of rowPanels) {
    panel.classList.add('dashboard-row-sized');
    panel.style.setProperty('--dashboard-row-height', `${Math.round(nextHeight)}px`);
  }
}

function handleDashboardResizeMouseUp(event) {
  void event;
  if (!state.dashboard.resizing.active) {
    return;
  }
  const rootKey = state.dashboard.resizing.rootKey;
  const signature = state.dashboard.resizing.rowSignature;
  const root = state.dashboard.rootElements.get(rootKey);
  if (root instanceof HTMLElement && signature) {
    const rows = dashboardRowsForRoot(root);
    const rowPanels = rows.find((row) => dashboardRowSignature(row) === signature);
    if (rowPanels && rowPanels.length > 0) {
      const maxHeight = Math.max(...rowPanels.map((panel) => panel.getBoundingClientRect().height));
      setDashboardRowHeight(rootKey, signature, maxHeight);
    }
  }
  state.dashboard.resizing.active = false;
  state.dashboard.resizing.rootKey = '';
  state.dashboard.resizing.rowSignature = '';
}

function handleDashboardRowResizeMouseDown(event) {
  const handle = event.target instanceof HTMLElement
    ? event.target.closest('.dashboard-row-resize-handle')
    : null;
  if (!(handle instanceof HTMLElement)) {
    return;
  }
  const rootKey = String(handle.dataset.rootKey || '').trim();
  const signature = String(handle.dataset.rowSignature || '').trim();
  if (!rootKey || !signature) {
    return;
  }
  const root = state.dashboard.rootElements.get(rootKey);
  if (!(root instanceof HTMLElement)) {
    return;
  }
  const rows = dashboardRowsForRoot(root);
  const rowPanels = rows.find((row) => dashboardRowSignature(row) === signature);
  if (!rowPanels || rowPanels.length === 0) {
    return;
  }

  const startHeight = Math.max(...rowPanels.map((panel) => panel.getBoundingClientRect().height));
  state.dashboard.resizing.active = true;
  state.dashboard.resizing.rootKey = rootKey;
  state.dashboard.resizing.rowSignature = signature;
  state.dashboard.resizing.startY = event.clientY;
  state.dashboard.resizing.startHeight = Math.max(DASHBOARD_MIN_ROW_HEIGHT, startHeight);
  event.preventDefault();
}

function ensureDashboardResizeBinding() {
  if (state.dashboard.resizeBound) {
    return;
  }
  document.addEventListener('mousedown', handleDashboardRowResizeMouseDown);
  document.addEventListener('mousemove', handleDashboardResizeMouseMove);
  document.addEventListener('mouseup', handleDashboardResizeMouseUp);
  window.addEventListener('resize', () => {
    requestAnimationFrame(() => {
      refreshAllDashboardRowSizing();
    });
  });
  state.dashboard.resizeBound = true;
}

function ensureControlsDashboardRoot(controlsPanel) {
  if (!(controlsPanel instanceof HTMLElement)) {
    return null;
  }

  let root = controlsPanel.querySelector(':scope > .controls-dashboard-root');
  if (!(root instanceof HTMLElement)) {
    root = document.createElement('div');
    root.className = 'controls-dashboard-root dashboard-layout-root';
    const firstSection = controlsPanel.querySelector(':scope > section');
    if (firstSection) {
      controlsPanel.insertBefore(root, firstSection);
    } else {
      controlsPanel.appendChild(root);
    }
  }

  const sections = Array.from(controlsPanel.querySelectorAll(':scope > section'));
  for (const section of sections) {
    root.appendChild(section);
  }
  return root;
}

function flattenDashboardPanelsIntoRoot(root, panelSelector) {
  const panels = Array.from(root.querySelectorAll(panelSelector)).filter((panel) => panel instanceof HTMLElement);
  for (const panel of panels) {
    if (panel.parentElement !== root) {
      root.appendChild(panel);
    }
  }
}

function cleanupDashboardRoots(root, selectors) {
  for (const selector of selectors) {
    const nodes = Array.from(root.querySelectorAll(selector)).filter((entry) => entry instanceof HTMLElement);
    for (const node of nodes) {
      if (node === root) {
        continue;
      }
      if (!node.querySelector('.subpanel') && !node.querySelector('section')) {
        node.remove();
      }
    }
  }
}

function assignDashboardPanelIds(rootKey, panels) {
  const seen = new Set();
  const counts = new Map();
  for (const panel of panels) {
    let itemId = String(panel.dataset.layoutItemId || '').trim();
    if (!itemId) {
      const preferred = String(panel.id || '').trim();
      const base = safeSlugToken(preferred || panelHeaderTitle(panel));
      const n = (counts.get(base) || 0) + 1;
      counts.set(base, n);
      itemId = `${rootKey}:${base}${n > 1 ? `:${n}` : ''}`;
    }
    while (seen.has(itemId)) {
      itemId = `${itemId}_x`;
    }
    panel.dataset.layoutItemId = itemId;
    panel.dataset.layoutRootKey = rootKey;
    seen.add(itemId);
  }
}

function applySavedDashboardLayout(rootKey, root) {
  const layout = state.dashboard.layouts?.[rootKey];
  const panels = dashboardRootPanels(root);
  const panelById = new Map();
  for (const panel of panels) {
    const itemId = String(panel.dataset.layoutItemId || '').trim();
    if (itemId) {
      panelById.set(itemId, panel);
    }
  }

  if (layout && Array.isArray(layout.order)) {
    for (const itemId of layout.order) {
      const key = String(itemId || '');
      const panel = panelById.get(key);
      if (!panel) {
        continue;
      }
      root.appendChild(panel);
      panelById.delete(key);
    }
    for (const panel of panelById.values()) {
      root.appendChild(panel);
    }
  }

  const savedSpans = layout && layout.spans && typeof layout.spans === 'object' ? layout.spans : {};
  for (const panel of dashboardRootPanels(root)) {
    const itemId = String(panel.dataset.layoutItemId || '').trim();
    const fallback = defaultDashboardSpan(rootKey, panel);
    panel.dataset.layoutSpan = normalizeDashboardSpan(savedSpans[itemId], fallback);
  }
  normalizeDashboardSpansForRoot(root);
}

function saveDashboardLayout(rootKey) {
  const root = state.dashboard.rootElements.get(rootKey);
  if (!(root instanceof HTMLElement)) {
    return;
  }
  normalizeDashboardSpansForRoot(root);

  const order = [];
  const spans = {};
  for (const panel of dashboardRootPanels(root)) {
    const itemId = String(panel.dataset.layoutItemId || '').trim();
    if (!itemId) {
      continue;
    }
    order.push(itemId);
    spans[itemId] = normalizeDashboardSpan(panel.dataset.layoutSpan, defaultDashboardSpan(rootKey, panel));
  }
  const prior = state.dashboard.layouts[rootKey] && typeof state.dashboard.layouts[rootKey] === 'object'
    ? state.dashboard.layouts[rootKey]
    : {};
  const rowHeights = prior.rowHeights && typeof prior.rowHeights === 'object'
    ? prior.rowHeights
    : {};
  state.dashboard.layouts[rootKey] = { order, spans, rowHeights };
  writeDashboardLayouts();
  refreshDashboardRowSizing(rootKey);
}

function clearDashboardDropState() {
  const highlighted = Array.from(document.querySelectorAll('.dashboard-panel.dashboard-drop-target'));
  for (const panel of highlighted) {
    panel.classList.remove('dashboard-drop-target', 'drop-left', 'drop-right', 'drop-above', 'drop-below');
  }
  state.dashboard.dropTargetItemId = '';
  state.dashboard.dropPosition = '';
}

function setDashboardDropState(panel, position) {
  if (!(panel instanceof HTMLElement) || !DASHBOARD_DROP_POSITIONS.has(position)) {
    return;
  }
  const itemId = String(panel.dataset.layoutItemId || '').trim();
  if (
    state.dashboard.dropTargetItemId === itemId
    && state.dashboard.dropPosition === position
  ) {
    return;
  }

  clearDashboardDropState();
  panel.classList.add('dashboard-drop-target', `drop-${position}`);
  state.dashboard.dropTargetItemId = itemId;
  state.dashboard.dropPosition = position;
}

function dashboardDropPosition(panel, event) {
  const rect = panel.getBoundingClientRect();
  const x = event.clientX - rect.left;
  const y = event.clientY - rect.top;
  const dx = x - rect.width * 0.5;
  const dy = y - rect.height * 0.5;
  const nx = rect.width > 0 ? dx / rect.width : 0;
  const ny = rect.height > 0 ? dy / rect.height : 0;
  if (Math.abs(nx) >= Math.abs(ny)) {
    return nx < 0 ? 'left' : 'right';
  }
  return ny < 0 ? 'above' : 'below';
}

function findDashboardPanelById(root, itemId) {
  for (const panel of dashboardRootPanels(root)) {
    if (String(panel.dataset.layoutItemId || '').trim() === itemId) {
      return panel;
    }
  }
  return null;
}

function notifyDashboardLayoutChanged(rootKey) {
  if (rootKey === 'vcdTab' && state.activeTab === 'vcdTab') {
    requestAnimationFrame(() => {
      window.dispatchEvent(new Event('resize'));
    });
    return;
  }
  if (rootKey === 'memoryTab' && state.activeTab === 'memoryTab') {
    requestAnimationFrame(() => {
      refreshMemoryView();
    });
    return;
  }
  if ((rootKey === 'componentTab' || rootKey === 'componentGraphTab') && isComponentTabActive()) {
    requestAnimationFrame(() => {
      refreshActiveComponentTab();
    });
  }
}

function applyDashboardDrop(targetPanel, position) {
  if (!(targetPanel instanceof HTMLElement) || !DASHBOARD_DROP_POSITIONS.has(position)) {
    return;
  }
  const rootKey = String(targetPanel.dataset.layoutRootKey || '').trim();
  if (!rootKey || rootKey !== state.dashboard.draggingRootKey) {
    return;
  }

  const root = state.dashboard.rootElements.get(rootKey);
  if (!(root instanceof HTMLElement)) {
    return;
  }
  const dragged = findDashboardPanelById(root, state.dashboard.draggingItemId);
  if (!(dragged instanceof HTMLElement) || dragged === targetPanel) {
    return;
  }

  if (position === 'left' || position === 'right') {
    dragged.dataset.layoutSpan = 'half';
    targetPanel.dataset.layoutSpan = 'half';
  } else {
    dragged.dataset.layoutSpan = 'full';
    targetPanel.dataset.layoutSpan = 'full';
  }

  if (position === 'left' || position === 'above') {
    root.insertBefore(dragged, targetPanel);
  } else {
    root.insertBefore(dragged, targetPanel.nextElementSibling);
  }
  normalizeDashboardSpansForRoot(root);

  saveDashboardLayout(rootKey);
  notifyDashboardLayoutChanged(rootKey);
}

function resetDashboardDragState() {
  const draggingPanels = Array.from(document.querySelectorAll('.dashboard-panel.is-dragging'));
  for (const panel of draggingPanels) {
    panel.classList.remove('is-dragging');
  }
  clearDashboardDropState();
  state.dashboard.draggingItemId = '';
  state.dashboard.draggingRootKey = '';
}

function handleDashboardDragStart(event) {
  const handle = event.currentTarget;
  const panel = handle instanceof HTMLElement ? handle.closest('.dashboard-panel') : null;
  if (!(panel instanceof HTMLElement)) {
    return;
  }

  const itemId = String(panel.dataset.layoutItemId || '').trim();
  const rootKey = String(panel.dataset.layoutRootKey || '').trim();
  if (!itemId || !rootKey) {
    return;
  }

  state.dashboard.draggingItemId = itemId;
  state.dashboard.draggingRootKey = rootKey;
  panel.classList.add('is-dragging');
  clearDashboardDropState();

  if (event.dataTransfer) {
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', itemId);
  }
}

function handleDashboardDragEnd() {
  resetDashboardDragState();
}

function handleDashboardDragOver(event) {
  const targetPanel = event.currentTarget;
  if (!(targetPanel instanceof HTMLElement)) {
    return;
  }
  const targetRootKey = String(targetPanel.dataset.layoutRootKey || '').trim();
  if (!targetRootKey || !state.dashboard.draggingItemId || targetRootKey !== state.dashboard.draggingRootKey) {
    return;
  }
  if (String(targetPanel.dataset.layoutItemId || '').trim() === state.dashboard.draggingItemId) {
    return;
  }

  event.preventDefault();
  const position = dashboardDropPosition(targetPanel, event);
  setDashboardDropState(targetPanel, position);
  if (event.dataTransfer) {
    event.dataTransfer.dropEffect = 'move';
  }
}

function handleDashboardDrop(event) {
  const targetPanel = event.currentTarget;
  if (!(targetPanel instanceof HTMLElement)) {
    return;
  }
  const targetRootKey = String(targetPanel.dataset.layoutRootKey || '').trim();
  if (!targetRootKey || !state.dashboard.draggingItemId || targetRootKey !== state.dashboard.draggingRootKey) {
    return;
  }
  if (String(targetPanel.dataset.layoutItemId || '').trim() === state.dashboard.draggingItemId) {
    resetDashboardDragState();
    return;
  }

  event.preventDefault();
  const position = DASHBOARD_DROP_POSITIONS.has(state.dashboard.dropPosition)
    ? state.dashboard.dropPosition
    : dashboardDropPosition(targetPanel, event);
  applyDashboardDrop(targetPanel, position);
  resetDashboardDragState();
}

function setupDashboardPanelInteractions(panel) {
  if (!(panel instanceof HTMLElement) || panel.dataset.dashboardReady === '1') {
    return;
  }
  const header = panel.querySelector(':scope > .panel-header-row');
  if (!(header instanceof HTMLElement)) {
    return;
  }

  header.classList.add('panel-drag-handle');
  header.setAttribute('draggable', 'true');
  header.addEventListener('dragstart', handleDashboardDragStart);
  header.addEventListener('dragend', handleDashboardDragEnd);
  panel.addEventListener('dragover', handleDashboardDragOver);
  panel.addEventListener('drop', handleDashboardDrop);
  const collapseBtn = panel.querySelector(':scope > .panel-header-row > .panel-collapse-btn');
  if (collapseBtn instanceof HTMLElement) {
    collapseBtn.setAttribute('draggable', 'false');
  }
  panel.dataset.dashboardReady = '1';
}

function initializeDashboardLayoutBuilder() {
  state.dashboard.layouts = readDashboardLayouts();
  state.dashboard.rootElements = new Map();
  resetDashboardDragState();
  ensureDashboardResizeBinding();

  for (const config of DASHBOARD_ROOT_CONFIGS) {
    const baseRoot = document.querySelector(config.selector);
    if (!(baseRoot instanceof HTMLElement)) {
      continue;
    }

    const root = config.wrapControls ? ensureControlsDashboardRoot(baseRoot) : baseRoot;
    if (!(root instanceof HTMLElement)) {
      continue;
    }

    root.classList.add('dashboard-layout-root');
    if (config.wrapControls) {
      root.classList.add('controls-dashboard-root');
    }

    if (config.flattenPanels) {
      flattenDashboardPanelsIntoRoot(root, config.panelSelector);
    }
    cleanupDashboardRoots(root, Array.isArray(config.cleanupSelectors) ? config.cleanupSelectors : []);

    const panels = Array.from(root.querySelectorAll(config.panelSelector))
      .filter((panel) => panel instanceof HTMLElement && panel.parentElement === root);
    assignDashboardPanelIds(config.key, panels);

    for (const panel of panels) {
      panel.classList.add('dashboard-panel');
      panel.dataset.layoutSpan = normalizeDashboardSpan(
        panel.dataset.layoutSpan,
        defaultDashboardSpan(config.key, panel)
      );
      setupDashboardPanelInteractions(panel);
    }

    const staticNodes = Array.from(root.children).filter((entry) => entry instanceof HTMLElement && !entry.classList.contains('dashboard-panel'));
    for (const node of staticNodes) {
      node.classList.add('dashboard-static');
    }
    for (const selector of config.staticSelectors || []) {
      const nodes = Array.from(root.querySelectorAll(selector)).filter((entry) => entry instanceof HTMLElement);
      for (const node of nodes) {
        if (node.parentElement === root) {
          node.classList.add('dashboard-static');
        }
      }
    }

    state.dashboard.rootElements.set(config.key, root);
    applySavedDashboardLayout(config.key, root);
    saveDashboardLayout(config.key);
  }
  refreshAllDashboardRowSizing();
}

function normalizeTheme(theme) {
  return theme === 'original' ? 'original' : 'shenzhen';
}

function waveformFontFamily() {
  return state.theme === 'shenzhen' ? 'Share Tech Mono' : 'IBM Plex Mono';
}

function waveformPalette() {
  if (state.theme === 'shenzhen') {
    return {
      bg: [8, 20, 18],
      axis: [66, 102, 85],
      grid: [46, 76, 62],
      label: [166, 198, 182],
      trace: [96, 234, 164],
      value: [244, 191, 102],
      time: [140, 164, 151],
      hint: [166, 198, 182]
    };
  }
  return {
    bg: [10, 21, 34],
    axis: [38, 74, 108],
    grid: [26, 56, 86],
    label: [152, 183, 217],
    trace: [61, 215, 194],
    value: [255, 188, 90],
    time: [153, 174, 200],
    hint: [170, 189, 212]
  };
}

function applyTheme(theme, { persist = true } = {}) {
  const nextTheme = normalizeTheme(theme);
  state.theme = nextTheme;
  if (document.body) {
    document.body.classList.toggle('theme-shenzhen', nextTheme === 'shenzhen');
  }
  if (dom.themeSelect && dom.themeSelect.value !== nextTheme) {
    dom.themeSelect.value = nextTheme;
  }
  if (state.waveformP5 && typeof state.waveformP5.textFont === 'function') {
    state.waveformP5.textFont(waveformFontFamily());
  }
  if (persist) {
    try {
      localStorage.setItem(THEME_KEY, nextTheme);
    } catch (_err) {
      // Ignore storage failures.
    }
  }
}

function resolveLiveSignalName(signalName, pathTokens, signalSet) {
  const raw = String(signalName || '').trim();
  if (!raw) {
    return null;
  }
  const normalized = raw.replace(/\./g, '__');
  const candidates = [raw, normalized];
  if (Array.isArray(pathTokens) && pathTokens.length > 0) {
    const joined = pathTokens.join('__');
    const tail = pathTokens[pathTokens.length - 1];
    candidates.push(`${joined}__${raw}`);
    candidates.push(`${joined}__${normalized}`);
    candidates.push(`${tail}__${raw}`);
    candidates.push(`${tail}__${normalized}`);
  }
  for (const candidate of candidates) {
    if (signalSet.has(candidate)) {
      return candidate;
    }
  }
  return null;
}

function nodeDisplayPath(node) {
  if (!node) {
    return 'top';
  }
  return node.path || node.name || 'top';
}

function makeComponentNode(model, parentId, name, kind, pathTokens = [], rawRef = null) {
  const id = `component_${model.nextId++}`;
  const path = pathTokens.length > 0 ? pathTokens.join('.') : 'top';
  const node = {
    id,
    parentId,
    name: String(name || 'component'),
    kind: String(kind || 'component'),
    path,
    pathTokens: Array.isArray(pathTokens) ? pathTokens : [],
    children: [],
    signals: [],
    rawRef,
    _signalKeys: new Set()
  };
  model.nodes.set(id, node);
  return node;
}

function addSignalToNode(node, signal) {
  if (!node || !signal) {
    return;
  }
  const key = signal.liveName || signal.fullName || signal.name;
  if (!key || node._signalKeys.has(key)) {
    return;
  }
  node._signalKeys.add(key);
  node.signals.push(signal);
}

function readSignalEntriesFromObject(obj) {
  const out = [];
  if (!obj || typeof obj !== 'object') {
    return out;
  }
  for (const kind of ['ports', 'nets', 'regs', 'signals', 'wires']) {
    const entries = Array.isArray(obj[kind]) ? obj[kind] : [];
    for (const entry of entries) {
      if (!entry || typeof entry.name !== 'string') {
        continue;
      }
      out.push({ kind, entry });
    }
  }
  return out;
}

function deriveComponentName(obj, fallback) {
  if (obj && typeof obj === 'object') {
    for (const key of ['instance_name', 'inst_name', 'instance', 'name', 'id', 'module', 'component', 'label']) {
      if (typeof obj[key] === 'string' && obj[key].trim()) {
        return obj[key].trim();
      }
    }
  }
  return fallback;
}

function summarizeIrEntry(entry) {
  if (!entry || typeof entry !== 'object') {
    return entry;
  }
  const summary = {};
  for (const key of ['name', 'kind', 'type', 'direction', 'width', 'clock', 'reset', 'path', 'file', 'line']) {
    if (entry[key] !== undefined) {
      summary[key] = entry[key];
    }
  }
  if (Object.keys(summary).length > 0) {
    return summary;
  }
  const keys = Object.keys(entry);
  return { keys: keys.slice(0, 12), fieldCount: keys.length };
}

function summarizeIrNode(rawRef) {
  if (!rawRef || typeof rawRef !== 'object') {
    return null;
  }
  const summary = {};
  for (const key of ['name', 'kind', 'type', 'instance', 'instance_name', 'module', 'component', 'path']) {
    if (rawRef[key] !== undefined) {
      summary[key] = rawRef[key];
    }
  }
  for (const key of ['ports', 'nets', 'regs', 'signals', 'processes', 'assigns', 'instances', 'children', 'modules', 'components']) {
    if (!Array.isArray(rawRef[key])) {
      continue;
    }
    const entries = rawRef[key];
    const limit = 40;
    summary[key] = entries.slice(0, limit).map(summarizeIrEntry);
    if (entries.length > limit) {
      summary[`${key}_truncated`] = entries.length - limit;
    }
  }
  return summary;
}

function signalGroupToken(name) {
  const raw = String(name || '').trim();
  if (!raw) {
    return null;
  }
  const match = raw.match(/^([a-z][a-z0-9]{1,24})[_./]/i);
  if (!match) {
    return null;
  }
  const token = match[1].toLowerCase();
  if (['next', 'prev', 'tmp', 'temp', 'process'].includes(token)) {
    return null;
  }
  return token;
}

function addSyntheticSignalGroupChildren(model, node, pathTokens) {
  if (!model || !node || !Array.isArray(node.signals) || node.signals.length < 16) {
    return 0;
  }

  const grouped = new Map();
  for (const signal of node.signals) {
    const token = signalGroupToken(signal.name || signal.fullName);
    if (!token) {
      continue;
    }
    if (!grouped.has(token)) {
      grouped.set(token, []);
    }
    grouped.get(token).push(signal);
  }

  const groups = Array.from(grouped.entries())
    .filter(([, signals]) => signals.length >= 2)
    .sort((a, b) => {
      const countDiff = b[1].length - a[1].length;
      if (countDiff !== 0) {
        return countDiff;
      }
      return a[0].localeCompare(b[0]);
    })
    .slice(0, 8);

  if (groups.length === 0) {
    return 0;
  }

  const siblingNames = new Set(
    node.children
      .map((childId) => model.nodes.get(childId)?.name?.toLowerCase())
      .filter(Boolean)
  );

  let added = 0;
  for (const [token, signals] of groups) {
    let childName = token;
    let suffix = 2;
    while (siblingNames.has(childName.toLowerCase())) {
      childName = `${token}_${suffix}`;
      suffix += 1;
    }
    siblingNames.add(childName.toLowerCase());

    const childPath = [...pathTokens, childName];
    const childNode = makeComponentNode(model, node.id, childName, 'signal-group', childPath, {
      name: childName,
      kind: 'signal-group',
      synthetic: true,
      signal_count: signals.length
    });
    for (const signal of signals) {
      addSignalToNode(childNode, signal);
    }
    node.children.push(childNode.id);
    added += 1;
  }
  return added;
}

function buildHierarchicalComponentModel(meta) {
  const ir = meta?.ir;
  if (!ir || typeof ir !== 'object') {
    return null;
  }

  const childKeys = ['children', 'instances', 'modules', 'components', 'submodules', 'blocks', 'units'];
  const hasExplicitHierarchy = childKeys.some((key) => Array.isArray(ir[key]) && ir[key].length > 0);
  if (!hasExplicitHierarchy) {
    return null;
  }

  const signalSet = new Set(meta?.liveSignalNames || meta?.names || []);
  const model = {
    nextId: 1,
    mode: 'hierarchical',
    nodes: new Map(),
    rootId: null
  };
  const rootName = typeof ir.name === 'string' && ir.name.trim() ? ir.name.trim() : 'top';
  const root = makeComponentNode(model, null, rootName, 'root', [], ir);
  model.rootId = root.id;

  const seen = new WeakSet();

  function walk(node, source, pathTokens) {
    if (!source || typeof source !== 'object') {
      return;
    }
    if (seen.has(source)) {
      return;
    }
    seen.add(source);

    for (const { kind, entry } of readSignalEntriesFromObject(source)) {
      const width = Number.parseInt(entry.width, 10) || 1;
      const liveName = resolveLiveSignalName(entry.name, pathTokens, signalSet);
      addSignalToNode(node, {
        name: entry.name,
        fullName: liveName || entry.name,
        liveName,
        width,
        kind,
        direction: entry.direction || null,
        declaration: entry
      });
    }

    let explicitChildCount = 0;
    for (const key of childKeys) {
      const children = Array.isArray(source[key]) ? source[key] : [];
      const siblingNames = new Set();
      children.forEach((child, index) => {
        if (!child || typeof child !== 'object') {
          return;
        }
        const baseName = deriveComponentName(child, `${key}_${index}`);
        let childName = baseName;
        let dedupe = 1;
        while (siblingNames.has(childName)) {
          dedupe += 1;
          childName = `${baseName}_${dedupe}`;
        }
        siblingNames.add(childName);

        const childPath = [...pathTokens, childName];
        const childNode = makeComponentNode(model, node.id, childName, key.slice(0, -1) || 'component', childPath, child);
        node.children.push(childNode.id);
        explicitChildCount += 1;
        walk(childNode, child, childPath);
      });
    }

    // Some modules (notably CPU cores) are authored as monolithic blocks with
    // no explicit instance hierarchy. Add grouped signal families as synthetic
    // child nodes so the graph can still be explored below this level.
    if (explicitChildCount === 0) {
      addSyntheticSignalGroupChildren(model, node, pathTokens);
    }
  }

  walk(root, ir, []);
  return model;
}

function buildDerivedFlatComponentModel(meta) {
  const model = {
    nextId: 1,
    mode: 'flat-derived',
    nodes: new Map(),
    rootId: null,
    pathMap: new Map()
  };
  const rootName = typeof meta?.ir?.name === 'string' && meta.ir.name.trim() ? meta.ir.name.trim() : 'top';
  const root = makeComponentNode(model, null, rootName, 'root', [], meta?.ir || null);
  model.rootId = root.id;
  model.pathMap.set('', root.id);

  function ensurePath(pathTokens) {
    const pathKey = pathTokens.join('__');
    if (model.pathMap.has(pathKey)) {
      return model.nodes.get(model.pathMap.get(pathKey));
    }
    const parentTokens = pathTokens.slice(0, -1);
    const parent = ensurePath(parentTokens);
    const name = pathTokens[pathTokens.length - 1];
    const node = makeComponentNode(model, parent.id, name, 'component', pathTokens, null);
    parent.children.push(node.id);
    model.pathMap.set(pathKey, node.id);
    return node;
  }

  for (const signalName of meta?.names || []) {
    const info = meta?.signalInfo?.get(signalName);
    const width = info?.width || (meta?.widths?.get(signalName) || 1);
    const parts = signalName.split('__').filter(Boolean);
    if (parts.length <= 1) {
      addSignalToNode(root, {
        name: signalName,
        fullName: signalName,
        liveName: signalName,
        width,
        kind: info?.kind || 'signal',
        direction: info?.direction || null,
        declaration: info?.entry || null
      });
      continue;
    }

    const pathTokens = parts.slice(0, -1);
    const leaf = parts[parts.length - 1];
    const node = ensurePath(pathTokens);
    addSignalToNode(node, {
      name: leaf,
      fullName: signalName,
      liveName: signalName,
      width,
      kind: info?.kind || 'signal',
      direction: info?.direction || null,
      declaration: info?.entry || null
    });
  }

  return model;
}

function finalizeComponentModel(model) {
  if (!model || !model.nodes) {
    return model;
  }
  for (const node of model.nodes.values()) {
    node.children.sort((a, b) => {
      const left = model.nodes.get(a);
      const right = model.nodes.get(b);
      return (left?.name || '').localeCompare(right?.name || '');
    });
    node.signals.sort((a, b) => (a.fullName || a.name || '').localeCompare(b.fullName || b.name || ''));
  }
  return model;
}

function buildComponentModel(meta) {
  const hierarchical = buildHierarchicalComponentModel(meta);
  if (hierarchical) {
    return finalizeComponentModel(hierarchical);
  }
  return finalizeComponentModel(buildDerivedFlatComponentModel(meta));
}

function nodeMatchesFilter(node, filter) {
  if (!filter) {
    return true;
  }
  const lower = filter.toLowerCase();
  if ((node.name || '').toLowerCase().includes(lower)) {
    return true;
  }
  if ((node.path || '').toLowerCase().includes(lower)) {
    return true;
  }
  for (const signal of node.signals) {
    const full = (signal.fullName || signal.name || '').toLowerCase();
    if (full.includes(lower)) {
      return true;
    }
  }
  return false;
}

function ensureComponentSelection() {
  const model = state.components.model;
  if (!model || !model.nodes.size) {
    state.components.selectedNodeId = null;
    return;
  }
  if (state.components.selectedNodeId && model.nodes.has(state.components.selectedNodeId)) {
    return;
  }
  state.components.selectedNodeId = model.rootId;
}

function ensureComponentGraphFocus() {
  const model = state.components.model;
  if (!model || !model.nodes.size) {
    state.components.graphFocusId = null;
    state.components.graphShowChildren = false;
    return;
  }
  if (state.components.graphFocusId && model.nodes.has(state.components.graphFocusId)) {
    return;
  }
  state.components.graphFocusId = model.rootId;
  state.components.graphShowChildren = true;
}

function currentComponentGraphFocusNode() {
  const model = state.components.model;
  if (!model || !model.nodes.size) {
    return null;
  }
  ensureComponentGraphFocus();
  const id = state.components.graphFocusId || model.rootId;
  return model.nodes.get(id) || model.nodes.get(model.rootId) || null;
}

function setComponentGraphFocus(nodeId, showChildren = true) {
  const model = state.components.model;
  if (!model || !nodeId || !model.nodes.has(nodeId)) {
    return;
  }
  state.components.graphFocusId = nodeId;
  state.components.graphShowChildren = !!showChildren;
  state.components.graphLastTap = null;
  state.components.graphHighlightedSignal = null;
  state.components.graphLiveValues = new Map();
  state.components.selectedNodeId = nodeId;
  renderComponentTree();
  renderComponentViews();
}

function renderComponentTree() {
  if (!dom.componentTree) {
    return;
  }

  dom.componentTree.innerHTML = '';

  if (state.components.parseError) {
    dom.componentTree.textContent = state.components.parseError;
    return;
  }

  const model = state.components.model;
  if (!model || !model.nodes.size) {
    dom.componentTree.textContent = 'Load valid IR to explore components.';
    return;
  }

  const filter = state.components.filter.trim().toLowerCase();
  const visibilityCache = new Map();

  function isVisible(nodeId) {
    if (!filter) {
      return true;
    }
    if (visibilityCache.has(nodeId)) {
      return visibilityCache.get(nodeId);
    }
    const node = model.nodes.get(nodeId);
    if (!node) {
      visibilityCache.set(nodeId, false);
      return false;
    }
    const visible = nodeMatchesFilter(node, filter) || node.children.some((childId) => isVisible(childId));
    visibilityCache.set(nodeId, visible);
    return visible;
  }

  function appendNode(nodeId, depth) {
    if (!isVisible(nodeId)) {
      return;
    }
    const node = model.nodes.get(nodeId);
    if (!node) {
      return;
    }

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'component-tree-node';
    if (nodeId === state.components.selectedNodeId) {
      button.classList.add('active');
    }
    button.dataset.componentId = nodeId;
    button.style.paddingLeft = `${8 + depth * 16}px`;

    const name = document.createElement('span');
    name.className = 'component-tree-name';
    name.textContent = node.name;
    button.appendChild(name);

    const kind = document.createElement('span');
    kind.className = 'component-tree-kind';
    kind.textContent = `[${node.kind}]`;
    button.appendChild(kind);

    const counts = document.createElement('span');
    counts.className = 'component-tree-count';
    counts.textContent = `${node.children.length}c ${node.signals.length}s`;
    button.appendChild(counts);

    dom.componentTree.appendChild(button);

    for (const childId of node.children) {
      appendNode(childId, depth + 1);
    }
  }

  appendNode(model.rootId, 0);
}

function currentSelectedComponentNode() {
  const model = state.components.model;
  if (!model || !state.components.selectedNodeId) {
    return null;
  }
  return model.nodes.get(state.components.selectedNodeId) || null;
}

function isComponentTabActive() {
  return state.activeTab === 'componentTab' || state.activeTab === 'componentGraphTab';
}

function renderComponentViews() {
  renderComponentInspector();
  renderComponentGraphPanel();
}

function refreshActiveComponentTab() {
  if (state.activeTab === 'componentTab') {
    renderComponentInspector();
  } else if (state.activeTab === 'componentGraphTab') {
    renderComponentGraphPanel();
  }
}

function destroyComponentGraph() {
  if (state.components.graph && typeof state.components.graph.destroy === 'function') {
    state.components.graph.destroy();
  }
  state.components.graph = null;
  state.components.graphKey = '';
  state.components.graphSelectedId = null;
  state.components.graphLastTap = null;
  state.components.graphLayoutEngine = 'none';
  state.components.graphElkAvailable = false;
}

function signalLiveValue(signal) {
  if (!state.sim || !signal?.liveName) {
    return null;
  }
  if (!state.irMeta?.widths?.has(signal.liveName)) {
    return null;
  }
  try {
    return state.sim.peek(signal.liveName);
  } catch (_err) {
    return null;
  }
}

function findComponentSourceEntry(node) {
  if (!node) {
    return null;
  }
  const byClass = state.components.sourceBundleByClass;
  const byModule = state.components.sourceBundleByModule;
  if (!(byClass instanceof Map) || !(byModule instanceof Map)) {
    return null;
  }

  const raw = node.rawRef && typeof node.rawRef === 'object' ? node.rawRef : null;
  const className = raw && typeof raw.component_class === 'string' ? raw.component_class.trim() : '';
  if (className && byClass.has(className)) {
    return byClass.get(className);
  }

  const moduleCandidates = [];
  if (raw) {
    for (const key of ['module_name', 'name', 'module', 'instance_name']) {
      const value = raw[key];
      if (typeof value === 'string' && value.trim()) {
        moduleCandidates.push(value.trim());
      }
    }
  }
  if (typeof node.name === 'string' && node.name.trim()) {
    moduleCandidates.push(node.name.trim());
  }
  for (const moduleName of moduleCandidates) {
    if (byModule.has(moduleName)) {
      return byModule.get(moduleName);
    }
    const lower = moduleName.toLowerCase();
    if (byModule.has(lower)) {
      return byModule.get(lower);
    }
  }

  const bundle = state.components.sourceBundle;
  if (bundle && bundle.top) {
    const model = state.components.model;
    if (!node.parentId || (model && node.id === model.rootId)) {
      return bundle.top;
    }
  }
  if (bundle && Array.isArray(bundle.components) && bundle.components.length === 1) {
    return bundle.components[0];
  }
  return null;
}

function formatSourceBackedComponentCode(node) {
  const entry = findComponentSourceEntry(node);
  if (!entry) {
    return null;
  }

  const view = normalizeComponentCodeView(state.components.codeView);
  const componentClass = String(entry.component_class || '').trim();
  const moduleName = String(entry.module_name || '').trim();
  const sourcePath = String(entry.source_path || '').trim();
  const rhdlSource = typeof entry.rhdl_source === 'string' ? entry.rhdl_source.trim() : '';
  const verilogSource = typeof entry.verilog_source === 'string' ? entry.verilog_source.trim() : '';

  if (view === 'rhdl') {
    if (!rhdlSource) {
      if (!verilogSource) {
        return null;
      }
      const fallbackHeader = ['// RHDL Ruby source not available; showing Verilog'];
      if (moduleName) {
        fallbackHeader.push(`module=${moduleName}`);
      }
      return `${fallbackHeader.join(' | ')}\n${verilogSource}`;
    }
    const headerBits = ['// RHDL Ruby source'];
    if (componentClass) {
      headerBits.push(`class=${componentClass}`);
    }
    if (sourcePath) {
      headerBits.push(`path=${sourcePath}`);
    }
    return `${headerBits.join(' | ')}\n${rhdlSource}`;
  }

  if (verilogSource) {
    const headerBits = ['// Verilog source'];
    if (moduleName) {
      headerBits.push(`module=${moduleName}`);
    }
    return `${headerBits.join(' | ')}\n${verilogSource}`;
  }

  if (rhdlSource) {
    const fallbackHeader = ['// Verilog source not available; showing RHDL Ruby'];
    if (componentClass) {
      fallbackHeader.push(`class=${componentClass}`);
    }
    if (sourcePath) {
      fallbackHeader.push(`path=${sourcePath}`);
    }
    return `${fallbackHeader.join(' | ')}\n${rhdlSource}`;
  }

  if (!rhdlSource && !verilogSource) {
    return null;
  }
  return null;
}

function formatComponentCode(node) {
  if (!node) {
    return 'Select a component to view details.';
  }

  const sourceCode = formatSourceBackedComponentCode(node);
  if (sourceCode) {
    return sourceCode;
  }

  const sections = [];
  if (node.rawRef) {
    const summary = summarizeIrNode(node.rawRef);
    if (summary) {
      sections.push('// IR node summary');
      sections.push(JSON.stringify(summary, null, 2));
    }
  }

  if (node.signals.length > 0) {
    const maxRows = 240;
    sections.push('// Signals');
    const rows = node.signals.slice(0, maxRows).map((signal) => {
      const direction = signal.direction ? ` (${signal.direction})` : '';
      return `${signal.kind.padEnd(6)} ${signal.fullName.padEnd(48)} width=${String(signal.width).padStart(2)}${direction}`;
    });
    if (node.signals.length > maxRows) {
      rows.push(`... ${node.signals.length - maxRows} more signals`);
    }
    sections.push(rows.join('\n'));
  }

  if (sections.length === 0) {
    return 'No IR/code details available for this component.';
  }
  return sections.join('\n\n');
}

function signalLiveValueByName(liveName) {
  if (!state.sim || !liveName) {
    return null;
  }
  try {
    return state.sim.peek(liveName);
  } catch (_err) {
    return null;
  }
}

function componentSignalLookup(node) {
  const lookup = new Map();
  if (!node) {
    return lookup;
  }
  for (const signal of node.signals || []) {
    if (signal?.name) {
      lookup.set(String(signal.name), signal);
    }
    if (signal?.fullName) {
      lookup.set(String(signal.fullName), signal);
    }
    if (signal?.liveName) {
      lookup.set(String(signal.liveName), signal);
    }
  }
  return lookup;
}

function resolveNodeSignalRef(node, lookup, signalName, width = 1, signalSet = null) {
  const localName = String(signalName || '').trim();
  if (!localName) {
    return null;
  }

  const signal = lookup?.get(localName) || null;
  if (signal) {
    const liveName = signal.liveName || signal.fullName || null;
    return {
      name: localName,
      liveName,
      width: signal.width || width || 1,
      valueKey: liveName || `${node?.path || 'top'}::${localName}`
    };
  }

  const fallbackSignalSet = signalSet || new Set(
    state.components.overrideMeta?.liveSignalNames
    || state.components.overrideMeta?.names
    || state.irMeta?.names
    || []
  );
  const liveName = resolveLiveSignalName(localName, node?.pathTokens || [], fallbackSignalSet);
  return {
    name: localName,
    liveName: liveName || null,
    width: width || 1,
    valueKey: liveName || `${node?.path || 'top'}::${localName}`
  };
}

function collectExprSignalNames(expr, out = new Set(), maxSignals = 20) {
  if (out.size >= maxSignals || expr == null) {
    return out;
  }
  if (Array.isArray(expr)) {
    for (const entry of expr) {
      collectExprSignalNames(entry, out, maxSignals);
      if (out.size >= maxSignals) {
        break;
      }
    }
    return out;
  }
  if (typeof expr !== 'object') {
    return out;
  }

  if (expr.type === 'signal' && typeof expr.name === 'string' && expr.name.trim()) {
    out.add(expr.name.trim());
    if (out.size >= maxSignals) {
      return out;
    }
  }

  for (const value of Object.values(expr)) {
    collectExprSignalNames(value, out, maxSignals);
    if (out.size >= maxSignals) {
      break;
    }
  }
  return out;
}

function componentCyIdForNode(nodeId) {
  return `cmp:${String(nodeId || '')}`;
}

function elementHasClass(element, className) {
  const classes = ` ${String(element?.classes || '')} `;
  return classes.includes(` ${className} `);
}

function computeComponentSchematicPositions(elements) {
  const nodes = elements.filter((element) => element && element.data && !element.data.source && !element.data.target);
  if (nodes.length === 0) {
    return new Map();
  }

  const hasRichSymbols = nodes.some((node) => elementHasClass(node, 'schem-symbol'));
  if (hasRichSymbols) {
    const positions = new Map();
    const symbolNodes = nodes.filter((node) => elementHasClass(node, 'schem-symbol'));
    const pinNodes = nodes.filter((node) => elementHasClass(node, 'schem-pin'));
    const netNodes = nodes.filter((node) => elementHasClass(node, 'schem-net'));
    const edgeElements = elements.filter((element) => element && element.data && element.data.source && element.data.target);

    const symbolPins = new Map();
    for (const pin of pinNodes) {
      const symbolId = String(pin.data.symbolId || '');
      if (!symbolId) {
        continue;
      }
      if (!symbolPins.has(symbolId)) {
        symbolPins.set(symbolId, { left: [], right: [], top: [], bottom: [] });
      }
      const side = String(pin.data.side || 'left').toLowerCase();
      const bucket = symbolPins.get(symbolId);
      if (Object.prototype.hasOwnProperty.call(bucket, side)) {
        bucket[side].push(pin);
      } else {
        bucket.left.push(pin);
      }
    }

    for (const buckets of symbolPins.values()) {
      for (const key of Object.keys(buckets)) {
        buckets[key].sort((a, b) => {
          const aOrder = Number.parseInt(a.data.order, 10) || 0;
          const bOrder = Number.parseInt(b.data.order, 10) || 0;
          if (aOrder !== bOrder) {
            return aOrder - bOrder;
          }
          return String(a.data.label || a.data.id).localeCompare(String(b.data.label || b.data.id));
        });
      }
    }

    const symbolById = new Map(symbolNodes.map((node) => [String(node.data.id), node]));
    const internalColumns = {
      components: [],
      focus: [],
      ops: [],
      memories: [],
      misc: []
    };
    const ioSymbols = [];

    for (const symbol of symbolNodes) {
      const symbolType = String(symbol.data.symbolType || '').toLowerCase();
      if (symbolType === 'io') {
        ioSymbols.push(symbol);
      } else if (symbolType === 'component') {
        internalColumns.components.push(symbol);
      } else if (symbolType === 'focus') {
        internalColumns.focus.push(symbol);
      } else if (symbolType === 'op') {
        internalColumns.ops.push(symbol);
      } else if (symbolType === 'memory') {
        internalColumns.memories.push(symbol);
      } else {
        internalColumns.misc.push(symbol);
      }
    }

    for (const list of Object.values(internalColumns)) {
      list.sort((a, b) => String(a.data.label || a.data.id).localeCompare(String(b.data.label || b.data.id)));
    }
    ioSymbols.sort((a, b) => String(a.data.label || a.data.id).localeCompare(String(b.data.label || b.data.id)));

    const internalCount = Object.values(internalColumns).reduce((sum, list) => sum + list.length, 0);
    if (internalCount === 0) {
      internalColumns.misc = [...symbolNodes];
      ioSymbols.length = 0;
    }

    const orderedInternal = [
      ...internalColumns.focus,
      ...internalColumns.components,
      ...internalColumns.memories,
      ...internalColumns.ops,
      ...internalColumns.misc
    ];

    const maxNodeWidth = Math.max(150, ...orderedInternal.map((node) => Math.max(92, Number.parseInt(node.data.symbolWidth, 10) || 150)));
    const maxNodeHeight = Math.max(72, ...orderedInternal.map((node) => Math.max(36, Number.parseInt(node.data.symbolHeight, 10) || 64)));
    const gridCols = Math.max(2, Math.ceil(Math.sqrt(Math.max(1, orderedInternal.length))));
    const colSpacing = maxNodeWidth + 260;
    const rowSpacing = maxNodeHeight + 210;
    const gridWidth = (gridCols - 1) * colSpacing;
    const originX = 760 - gridWidth * 0.5;
    const originY = 220;
    const symbolGeometry = new Map();
    const internalNodeIds = [];

    orderedInternal.forEach((node, index) => {
      const col = index % gridCols;
      const row = Math.floor(index / gridCols);
      const x = originX + col * colSpacing + ((row % 2) * (colSpacing * 0.2));
      const y = originY + row * rowSpacing;
      positions.set(node.data.id, { x, y });
      const width = Math.max(92, Number.parseInt(node.data.symbolWidth, 10) || 150);
      const height = Math.max(36, Number.parseInt(node.data.symbolHeight, 10) || 64);
      symbolGeometry.set(node.data.id, { x, y, width, height });
      internalNodeIds.push(String(node.data.id));
    });

    if (ioSymbols.length > 0 && internalNodeIds.length > 0) {
      let minLeft = Infinity;
      let maxRight = -Infinity;
      let minTop = Infinity;
      let maxBottom = -Infinity;
      for (const id of internalNodeIds) {
        const geom = symbolGeometry.get(id);
        if (!geom) {
          continue;
        }
        minLeft = Math.min(minLeft, geom.x - geom.width * 0.5);
        maxRight = Math.max(maxRight, geom.x + geom.width * 0.5);
        minTop = Math.min(minTop, geom.y - geom.height * 0.5);
        maxBottom = Math.max(maxBottom, geom.y + geom.height * 0.5);
      }

      const ring = {
        left: minLeft - 210,
        right: maxRight + 210,
        top: minTop - 160,
        bottom: maxBottom + 160
      };

      const ioIn = ioSymbols.filter((node) => String(node.data.direction || '').toLowerCase() === 'in');
      const ioOut = ioSymbols.filter((node) => String(node.data.direction || '').toLowerCase() === 'out');
      const ioOther = ioSymbols.filter((node) => {
        const dir = String(node.data.direction || '').toLowerCase();
        return dir !== 'in' && dir !== 'out';
      });
      const orderedIo = [...ioIn, ...ioOther, ...ioOut];

      const sideBuckets = {
        top: [],
        right: [],
        bottom: [],
        left: []
      };
      for (let idx = 0; idx < orderedIo.length; idx += 1) {
        const ratio = idx / Math.max(1, orderedIo.length);
        const sideIdx = Math.min(3, Math.floor(ratio * 4));
        const side = sideIdx === 0
          ? 'top'
          : sideIdx === 1
            ? 'right'
            : sideIdx === 2
              ? 'bottom'
              : 'left';
        sideBuckets[side].push(orderedIo[idx]);
      }

      let spanX = ring.right - ring.left;
      let spanY = ring.bottom - ring.top;
      const minSpanX = Math.max(560, Math.max(sideBuckets.top.length, sideBuckets.bottom.length) * 96 + 180);
      const minSpanY = Math.max(420, Math.max(sideBuckets.left.length, sideBuckets.right.length) * 74 + 150);
      if (spanX < minSpanX) {
        const delta = (minSpanX - spanX) * 0.5;
        ring.left -= delta;
        ring.right += delta;
        spanX = ring.right - ring.left;
      }
      if (spanY < minSpanY) {
        const delta = (minSpanY - spanY) * 0.5;
        ring.top -= delta;
        ring.bottom += delta;
        spanY = ring.bottom - ring.top;
      }

      const topPadX = 84;
      const sidePadY = 72;
      const placeSideNodes = (list, side) => {
        const count = list.length;
        if (count === 0) {
          return;
        }
        for (let idx = 0; idx < count; idx += 1) {
          const node = list[idx];
          const t = (idx + 1) / (count + 1);
          let x = (ring.left + ring.right) * 0.5;
          let y = (ring.top + ring.bottom) * 0.5;
          if (side === 'top') {
            x = ring.left + topPadX + t * (spanX - topPadX * 2);
            y = ring.top;
          } else if (side === 'right') {
            x = ring.right;
            y = ring.top + sidePadY + t * (spanY - sidePadY * 2);
          } else if (side === 'bottom') {
            x = ring.right - topPadX - t * (spanX - topPadX * 2);
            y = ring.bottom;
          } else {
            x = ring.left;
            y = ring.bottom - sidePadY - t * (spanY - sidePadY * 2);
          }
          positions.set(node.data.id, { x, y });
          const width = Math.max(26, Number.parseInt(node.data.symbolWidth, 10) || 34);
          const height = Math.max(12, Number.parseInt(node.data.symbolHeight, 10) || 16);
          symbolGeometry.set(node.data.id, { x, y, width, height });
        }
      };

      placeSideNodes(sideBuckets.top, 'top');
      placeSideNodes(sideBuckets.right, 'right');
      placeSideNodes(sideBuckets.bottom, 'bottom');
      placeSideNodes(sideBuckets.left, 'left');
    }

    for (const [symbolId, buckets] of symbolPins.entries()) {
      const symbol = symbolById.get(symbolId);
      const symbolType = String(symbol?.data?.symbolType || '').toLowerCase();
      if (symbolType === 'component' || symbolType === 'focus') {
        const allPins = [...buckets.left, ...buckets.right, ...buckets.top, ...buckets.bottom];
        allPins.sort((a, b) => {
          const aOrder = Number.parseInt(a.data.order, 10) || 0;
          const bOrder = Number.parseInt(b.data.order, 10) || 0;
          if (aOrder !== bOrder) {
            return aOrder - bOrder;
          }
          return String(a.data.label || a.data.id).localeCompare(String(b.data.label || b.data.id));
        });
        const redistributed = { left: [], right: [], top: [], bottom: [] };
        const cycle = ['left', 'top', 'right', 'bottom'];
        for (let idx = 0; idx < allPins.length; idx += 1) {
          const side = cycle[idx % cycle.length];
          redistributed[side].push(allPins[idx]);
        }
        symbolPins.set(symbolId, redistributed);
      }
    }

    for (const pin of pinNodes) {
      const symbolId = String(pin.data.symbolId || '');
      const side = String(pin.data.side || 'left').toLowerCase();
      const geom = symbolGeometry.get(symbolId);
      if (!geom) {
        continue;
      }
      const bucket = symbolPins.get(symbolId) || { left: [], right: [], top: [], bottom: [] };
      let effectiveSide = side;
      if (!(bucket[effectiveSide] && bucket[effectiveSide].length > 0)) {
        const fallbackSide = ['left', 'right', 'top', 'bottom'].find((key) => bucket[key] && bucket[key].some((entry) => entry.data.id === pin.data.id));
        effectiveSide = fallbackSide || 'left';
      }
      const sidePins = bucket[effectiveSide] || bucket.left || [];
      const idx = Math.max(0, sidePins.findIndex((entry) => entry.data.id === pin.data.id));
      const count = Math.max(1, sidePins.length);
      let x = geom.x;
      let y = geom.y;
      if (effectiveSide === 'left' || effectiveSide === 'right') {
        y = geom.y - geom.height * 0.5 + ((idx + 1) * geom.height) / (count + 1);
        x = effectiveSide === 'left' ? geom.x - geom.width * 0.5 - 36 : geom.x + geom.width * 0.5 + 36;
      } else {
        x = geom.x - geom.width * 0.5 + ((idx + 1) * geom.width) / (count + 1);
        y = effectiveSide === 'top' ? geom.y - geom.height * 0.5 - 26 : geom.y + geom.height * 0.5 + 26;
      }
      positions.set(pin.data.id, { x, y });
    }

    const netIds = new Set(netNodes.map((node) => String(node.data.id)));
    const pinIds = new Set(pinNodes.map((node) => String(node.data.id)));
    const netPointMap = new Map();
    for (const net of netNodes) {
      netPointMap.set(String(net.data.id), []);
    }

    for (const edge of edgeElements) {
      const source = String(edge.data.source || '');
      const target = String(edge.data.target || '');
      if (netIds.has(source) && pinIds.has(target) && positions.has(target)) {
        netPointMap.get(source).push(positions.get(target));
      } else if (netIds.has(target) && pinIds.has(source) && positions.has(source)) {
        netPointMap.get(target).push(positions.get(source));
      }
    }

    const netLane = new Map();
    let fallbackY = 120;
    for (const net of netNodes.sort((a, b) => String(a.data.label || a.data.id).localeCompare(String(b.data.label || b.data.id)))) {
      const netId = String(net.data.id);
      const points = netPointMap.get(netId) || [];
      let x = 700;
      let y = fallbackY;
      if (points.length > 0) {
        x = points.reduce((sum, pt) => sum + pt.x, 0) / points.length;
        y = points.reduce((sum, pt) => sum + pt.y, 0) / points.length;
      } else {
        fallbackY += 28;
      }
      const laneKey = `${Math.round(x / 16)}:${Math.round(y / 16)}`;
      const laneCount = netLane.get(laneKey) || 0;
      netLane.set(laneKey, laneCount + 1);
      if (laneCount > 0) {
        y += laneCount * 14;
      }
      positions.set(netId, { x, y });
    }

    return positions;
  }

  const columns = {
    ioIn: [],
    components: [],
    focus: [],
    ops: [],
    memories: [],
    nets: [],
    ioOut: [],
    misc: []
  };

  for (const node of nodes) {
    if (elementHasClass(node, 'schem-io-in')) {
      columns.ioIn.push(node.data.id);
      continue;
    }
    if (elementHasClass(node, 'schem-io-out')) {
      columns.ioOut.push(node.data.id);
      continue;
    }
    if (elementHasClass(node, 'schem-focus')) {
      columns.focus.push(node.data.id);
      continue;
    }
    if (elementHasClass(node, 'schem-component')) {
      columns.components.push(node.data.id);
      continue;
    }
    if (elementHasClass(node, 'schem-op')) {
      columns.ops.push(node.data.id);
      continue;
    }
    if (elementHasClass(node, 'schem-memory')) {
      columns.memories.push(node.data.id);
      continue;
    }
    if (elementHasClass(node, 'schem-net')) {
      columns.nets.push(node.data.id);
      continue;
    }
    columns.misc.push(node.data.id);
  }

  for (const list of Object.values(columns)) {
    list.sort((a, b) => String(a).localeCompare(String(b)));
  }

  const orderedColumns = [
    { ids: columns.ioIn, x: 110 },
    { ids: columns.components, x: 360 },
    { ids: columns.focus, x: 580 },
    { ids: columns.ops, x: 800 },
    { ids: columns.memories, x: 950 },
    { ids: columns.nets, x: 1140 },
    { ids: columns.ioOut, x: 1360 },
    { ids: columns.misc, x: 1520 }
  ];

  const maxRows = Math.max(1, ...orderedColumns.map((column) => column.ids.length));
  const rowSpacing = 50;
  const topY = 80;
  const positions = new Map();

  for (const column of orderedColumns) {
    if (column.ids.length === 0) {
      continue;
    }
    const offset = (maxRows - column.ids.length) * rowSpacing * 0.5;
    column.ids.forEach((id, index) => {
      positions.set(id, {
        x: column.x,
        y: topY + offset + index * rowSpacing
      });
    });
  }

  return positions;
}

function findComponentSchematicEntry(node) {
  if (!node) {
    return null;
  }
  const byPath = state.components.schematicBundleByPath;
  if (!(byPath instanceof Map) || byPath.size === 0) {
    return null;
  }
  const path = String(node.path || 'top');
  return byPath.get(path) || null;
}

function createComponentSchematicElementsFromExport(model, focusNode, showChildren, schematicEntry) {
  const elements = [];
  if (!model || !focusNode || !schematicEntry || typeof schematicEntry !== 'object') {
    return elements;
  }
  const schematic = schematicEntry.schematic;
  if (!schematic || typeof schematic !== 'object') {
    return elements;
  }

  const lookup = componentSignalLookup(focusNode);
  const seenNodes = new Set();
  const seenEdges = new Set();
  let edgeSeq = 0;

  const pathToNodeId = new Map();
  for (const node of model.nodes.values()) {
    pathToNodeId.set(String(node.path || ''), node.id);
  }

  const normalizeSignal = (name, width = 1, liveName = null) => {
    const signalName = String(name || '').trim();
    if (!signalName) {
      return null;
    }
    const ref = resolveNodeSignalRef(focusNode, lookup, signalName, width);
    const explicitLive = String(liveName || '').trim();
    if (explicitLive) {
      ref.liveName = explicitLive;
      ref.valueKey = explicitLive;
    }
    return ref;
  };

  const pushNode = (id, data, classes = '') => {
    if (!id || seenNodes.has(id)) {
      return;
    }
    seenNodes.add(id);
    elements.push({
      data: {
        id,
        ...data
      },
      classes
    });
  };

  const pushEdge = (source, target, data = {}, classes = '') => {
    if (!source || !target || !seenNodes.has(source) || !seenNodes.has(target)) {
      return;
    }
    edgeSeq += 1;
    const base = data.id || `wire:${source}:${target}:${edgeSeq}`;
    let id = base;
    while (seenEdges.has(id)) {
      edgeSeq += 1;
      id = `${base}:${edgeSeq}`;
    }
    seenEdges.add(id);
    elements.push({
      data: {
        id,
        source,
        target,
        ...data
      },
      classes
    });
  };

  const pins = Array.isArray(schematic.pins) ? schematic.pins : [];
  const pinCountBySymbol = new Map();
  for (const pin of pins) {
    const symbolId = String(pin?.symbol_id || '').trim();
    const side = String(pin?.side || 'left').trim().toLowerCase();
    if (!symbolId) {
      continue;
    }
    if (!pinCountBySymbol.has(symbolId)) {
      pinCountBySymbol.set(symbolId, { left: 0, right: 0, top: 0, bottom: 0 });
    }
    const counts = pinCountBySymbol.get(symbolId);
    if (Object.prototype.hasOwnProperty.call(counts, side)) {
      counts[side] += 1;
    } else {
      counts.left += 1;
    }
  }

  const symbolIdSet = new Set();
  const netIdSet = new Set();
  const pinIdSet = new Set();
  const netSignalById = new Map();
  const hideTopFocusSymbol = String(focusNode.path || 'top') === 'top';

  const symbols = Array.isArray(schematic.symbols) ? schematic.symbols : [];
  for (const symbol of symbols) {
    if (!symbol || typeof symbol !== 'object') {
      continue;
    }
    const symbolId = String(symbol.id || '').trim();
    if (!symbolId) {
      continue;
    }
    const symbolType = String(symbol.type || 'component').trim().toLowerCase();
    const componentPath = String(symbol.component_path || '').trim();
    if (hideTopFocusSymbol && symbolType === 'focus') {
      continue;
    }
    const isChildComponent = symbolType === 'component' && componentPath && componentPath !== String(focusNode.path || 'top');
    if (!showChildren && isChildComponent) {
      continue;
    }

    const componentId = (() => {
      if (symbolType === 'focus') {
        return focusNode.id;
      }
      if (!componentPath) {
        return '';
      }
      return String(pathToNodeId.get(componentPath) || '');
    })();

    const direction = String(symbol.direction || '').trim().toLowerCase();
    const counts = pinCountBySymbol.get(symbolId) || { left: 0, right: 0, top: 0, bottom: 0 };
    const verticalPins = Math.max(counts.left, counts.right);
    const horizontalPins = Math.max(counts.top, counts.bottom);
    const baseWidth = symbolType === 'focus'
      ? 228
      : symbolType === 'component'
        ? 178
        : symbolType === 'memory'
          ? 118
          : symbolType === 'op'
            ? 102
            : symbolType === 'io'
              ? 34
              : 112;
    const baseHeight = symbolType === 'focus'
      ? 94
      : symbolType === 'component'
        ? 72
        : symbolType === 'memory'
          ? 54
          : symbolType === 'op'
            ? 42
            : symbolType === 'io'
              ? 16
              : 46;
    const scalable = symbolType === 'focus' || symbolType === 'component' || symbolType === 'memory';
    const symbolWidth = scalable
      ? Math.min(420, Math.max(baseWidth, baseWidth + Math.max(0, horizontalPins - 4) * 10))
      : baseWidth;
    const symbolHeight = scalable
      ? Math.min(420, Math.max(baseHeight, baseHeight + Math.max(0, verticalPins - 4) * 12))
      : baseHeight;

    const classes = [
      'schem-symbol',
      symbolType === 'focus' || symbolType === 'component' ? 'schem-component' : '',
      symbolType === 'focus' ? 'schem-focus' : '',
      symbolType === 'io' ? `schem-io ${direction === 'in' ? 'schem-io-in' : direction === 'out' ? 'schem-io-out' : ''}` : '',
      symbolType === 'memory' ? 'schem-memory' : '',
      symbolType === 'op' ? 'schem-op' : ''
    ].filter(Boolean).join(' ');

    pushNode(symbolId, {
      label: String(symbol.label || symbol.name || symbolId),
      nodeRole: 'symbol',
      symbolType,
      componentId,
      path: componentPath || '',
      direction,
      symbolWidth,
      symbolHeight
    }, classes);
    symbolIdSet.add(symbolId);
  }

  const nets = Array.isArray(schematic.nets) ? schematic.nets : [];
  for (const net of nets) {
    if (!net || typeof net !== 'object') {
      continue;
    }
    const netId = String(net.id || '').trim();
    const signalName = String(net.name || net.signal || '').trim();
    if (!netId || !signalName) {
      continue;
    }
    const width = Number.parseInt(net.width, 10) || 1;
    const signalRef = normalizeSignal(signalName, width, net.live_name);
    const classes = ['schem-net'];
    if ((signalRef?.width || width || 1) > 1 || net.bus) {
      classes.push('schem-bus');
    }
    pushNode(netId, {
      label: ellipsizeText(signalName, 18),
      nodeRole: 'net',
      signalName: signalRef?.name || signalName,
      liveName: signalRef?.liveName || '',
      valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
      width: signalRef?.width || width || 1,
      group: String(net.group || '')
    }, classes.join(' '));
    netIdSet.add(netId);
    netSignalById.set(netId, {
      signalName: signalRef?.name || signalName,
      liveName: signalRef?.liveName || '',
      valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
      width: signalRef?.width || width || 1
    });
  }

  for (const pin of pins) {
    if (!pin || typeof pin !== 'object') {
      continue;
    }
    const pinId = String(pin.id || '').trim();
    const symbolId = String(pin.symbol_id || '').trim();
    if (!pinId || !symbolId || !symbolIdSet.has(symbolId)) {
      continue;
    }

    const signalName = String(pin.signal || pin.name || '').trim();
    const width = Number.parseInt(pin.width, 10) || 1;
    const signalRef = signalName ? normalizeSignal(signalName, width, pin.live_name) : null;
    const side = ['left', 'right', 'top', 'bottom'].includes(String(pin.side || '').toLowerCase())
      ? String(pin.side || '').toLowerCase()
      : 'left';
    const direction = String(pin.direction || 'inout').toLowerCase();
    const classes = ['schem-pin', `schem-pin-${side}`];
    if ((signalRef?.width || width || 1) > 1 || pin.bus) {
      classes.push('schem-bus');
    }

    pushNode(pinId, {
      label: String(pin.name || signalRef?.name || pinId),
      nodeRole: 'pin',
      symbolId,
      side,
      order: Number.parseInt(pin.order, 10) || 0,
      direction,
      signalName: signalRef?.name || signalName,
      liveName: signalRef?.liveName || '',
      valueKey: signalRef?.valueKey || (signalName ? `${focusNode.path}::${signalName}` : ''),
      width: signalRef?.width || width || 1
    }, classes.join(' '));
    pinIdSet.add(pinId);
  }

  const wires = Array.isArray(schematic.wires) ? schematic.wires : [];
  for (const wire of wires) {
    if (!wire || typeof wire !== 'object') {
      continue;
    }
    const fromPinId = String(wire.from_pin_id || '').trim();
    const toPinId = String(wire.to_pin_id || '').trim();
    let netId = String(wire.net_id || '').trim();
    if (!fromPinId || !toPinId) {
      continue;
    }
    const hasFrom = pinIdSet.has(fromPinId);
    const hasTo = pinIdSet.has(toPinId);
    if (!hasFrom && !hasTo) {
      continue;
    }

    if (!netId || !netIdSet.has(netId)) {
      const signalName = String(wire.signal || '').trim();
      if (!signalName) {
        continue;
      }
      const width = Number.parseInt(wire.width, 10) || 1;
      const signalRef = normalizeSignal(signalName, width, wire.live_name);
      netId = `net:${focusNode.id}:${signalRef?.name || signalName}`;
      if (!netIdSet.has(netId)) {
        pushNode(netId, {
          label: ellipsizeText(signalRef?.name || signalName, 18),
          nodeRole: 'net',
          signalName: signalRef?.name || signalName,
          liveName: signalRef?.liveName || '',
          valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
          width: signalRef?.width || width || 1
        }, (signalRef?.width || width || 1) > 1 ? 'schem-net schem-bus' : 'schem-net');
        netIdSet.add(netId);
      }
      netSignalById.set(netId, {
        signalName: signalRef?.name || signalName,
        liveName: signalRef?.liveName || '',
        valueKey: signalRef?.valueKey || `${focusNode.path}::${signalName}`,
        width: signalRef?.width || width || 1
      });
    }

    const netSignal = netSignalById.get(netId) || {};
    const direction = String(wire.direction || 'inout').toLowerCase();
    const width = Number.parseInt(wire.width, 10) || netSignal.width || 1;
    const signalName = String(wire.signal || netSignal.signalName || '').trim();
    const liveName = String(wire.live_name || netSignal.liveName || '').trim();
    const valueKey = String(netSignal.valueKey || (signalName ? `${focusNode.path}::${signalName}` : '')).trim();
    const wireKind = String(wire.kind || 'wire').trim();

    const classes = ['schem-wire', `schem-kind-${wireKind.replace(/[^a-zA-Z0-9_-]+/g, '_')}`];
    if (width > 1) {
      classes.push('schem-bus');
    }
    if (direction === 'inout') {
      classes.push('schem-bidir');
    }

    const edgeData = {
      signalName,
      liveName,
      valueKey,
      width,
      direction,
      kind: wireKind,
      wireId: String(wire.id || ''),
      netId
    };

    if (hasFrom) {
      pushEdge(fromPinId, netId, { ...edgeData, segment: 'from', id: `${wire.id || `${fromPinId}:${netId}`}:from` }, classes.join(' '));
    }
    if (hasTo) {
      pushEdge(netId, toPinId, { ...edgeData, segment: 'to', id: `${wire.id || `${netId}:${toPinId}`}:to` }, classes.join(' '));
    }
  }

  return elements;
}

function createComponentSchematicElements(model, focusNode, showChildren) {
  const elements = [];
  if (!model || !focusNode) {
    return elements;
  }

  const schematicEntry = findComponentSchematicEntry(focusNode);
  if (schematicEntry) {
    return createComponentSchematicElementsFromExport(model, focusNode, showChildren, schematicEntry);
  }

  const lookup = componentSignalLookup(focusNode);
  const liveSignalSet = new Set(
    state.components.overrideMeta?.liveSignalNames
    || state.components.overrideMeta?.names
    || state.irMeta?.names
    || []
  );
  const raw = focusNode.rawRef && typeof focusNode.rawRef === 'object' ? focusNode.rawRef : {};
  const seenNodes = new Set();
  const seenEdges = new Set();
  const netNodes = new Map();
  let edgeSeq = 0;

  const pushNode = (id, data, classes = '') => {
    if (!id || seenNodes.has(id)) {
      return;
    }
    seenNodes.add(id);
    elements.push({
      data: {
        id,
        ...data
      },
      classes
    });
  };

  const pushEdge = (source, target, data = {}, classes = '') => {
    if (!source || !target) {
      return;
    }
    edgeSeq += 1;
    const base = data.id || `wire:${source}:${target}:${edgeSeq}`;
    let id = base;
    while (seenEdges.has(id)) {
      edgeSeq += 1;
      id = `${base}:${edgeSeq}`;
    }
    seenEdges.add(id);
    elements.push({
      data: {
        id,
        source,
        target,
        ...data
      },
      classes
    });
  };

  const ensureNet = (name, width = 1) => {
    const signalName = String(name || '').trim();
    if (!signalName) {
      return null;
    }
    if (netNodes.has(signalName)) {
      return netNodes.get(signalName);
    }
    const ref = resolveNodeSignalRef(focusNode, lookup, signalName, width, liveSignalSet);
    const id = `net:${focusNode.id}:${signalName}`;
    pushNode(id, {
      label: signalName,
      nodeRole: 'net',
      signalName: ref?.name || signalName,
      liveName: ref?.liveName || '',
      valueKey: ref?.valueKey || `${focusNode.path}::${signalName}`,
      width: ref?.width || width || 1
    }, 'schem-net');
    netNodes.set(signalName, id);
    return id;
  };

  const addPortEdge = (fromId, toId, signalRef, direction, kind = 'port') => {
    if (!fromId || !toId || !signalRef) {
      return;
    }
    const edgeData = {
      signalName: signalRef.name,
      liveName: signalRef.liveName || '',
      valueKey: signalRef.valueKey,
      width: signalRef.width || 1,
      direction: direction || '?',
      kind
    };
    if (direction === 'in') {
      pushEdge(fromId, toId, edgeData, 'schem-wire schem-port-wire');
    } else if (direction === 'out') {
      pushEdge(toId, fromId, edgeData, 'schem-wire schem-port-wire');
    } else {
      pushEdge(fromId, toId, edgeData, 'schem-wire schem-port-wire schem-bidir');
    }
  };

  const focusCyId = componentCyIdForNode(focusNode.id);
  pushNode(focusCyId, {
    label: focusNode.name,
    nodeRole: 'component',
    componentId: focusNode.id,
    isFocus: 1,
    path: focusNode.path,
    signals: focusNode.signals.length,
    children: focusNode.children.length
  }, 'schem-component schem-focus schem-component-fallback');

  const rawPorts = Array.isArray(raw.ports) ? raw.ports : [];
  const maxIoPorts = 120;
  for (const port of rawPorts.slice(0, maxIoPorts)) {
    if (!port || typeof port.name !== 'string') {
      continue;
    }
    const signalRef = resolveNodeSignalRef(focusNode, lookup, port.name, Number.parseInt(port.width, 10) || 1, liveSignalSet);
    const netId = ensureNet(port.name, signalRef?.width || 1);
    if (!netId || !signalRef) {
      continue;
    }
    const direction = String(port.direction || '?').toLowerCase();
    const ioId = `io:${focusNode.id}:${signalRef.name}`;
    const ioClass = direction === 'in'
      ? 'schem-io schem-io-in'
      : direction === 'out'
        ? 'schem-io schem-io-out'
        : 'schem-io';
    pushNode(ioId, {
      label: signalRef.name,
      nodeRole: 'io',
      signalName: signalRef.name,
      liveName: signalRef.liveName || '',
      valueKey: signalRef.valueKey,
      direction
    }, ioClass);
    addPortEdge(ioId, netId, signalRef, direction, 'io-port');
  }

  const shouldShowChildren = !!showChildren;
  if (shouldShowChildren) {
    for (const childId of focusNode.children || []) {
      const childNode = model.nodes.get(childId);
      if (!childNode) {
        continue;
      }
      const childCyId = componentCyIdForNode(childNode.id);
      const childLabel = childNode.kind === 'signal-group'
        ? `${childNode.name} [signals]`
        : childNode.name;
      pushNode(childCyId, {
        label: childLabel,
        nodeRole: 'component',
        componentId: childNode.id,
        isFocus: 0,
        path: childNode.path,
        signals: childNode.signals.length,
        children: childNode.children.length
      }, 'schem-component schem-component-fallback');

      const childRaw = childNode.rawRef && typeof childNode.rawRef === 'object' ? childNode.rawRef : {};
      const childPorts = Array.isArray(childRaw.ports) ? childRaw.ports : [];
      for (const port of childPorts) {
        if (!port || typeof port.name !== 'string') {
          continue;
        }
        const signalRef = resolveNodeSignalRef(focusNode, lookup, port.name, Number.parseInt(port.width, 10) || 1, liveSignalSet);
        const netId = ensureNet(port.name, signalRef?.width || 1);
        if (!netId || !signalRef) {
          continue;
        }
        const direction = String(port.direction || '?').toLowerCase();
        addPortEdge(netId, childCyId, signalRef, direction, 'child-port');
      }
    }
  }

  const memoryNodes = new Set();
  const ensureMemoryNode = (name) => {
    const memoryName = String(name || '').trim();
    if (!memoryName) {
      return null;
    }
    const id = `mem:${focusNode.id}:${memoryName}`;
    if (!memoryNodes.has(id)) {
      memoryNodes.add(id);
      pushNode(id, {
        label: memoryName,
        nodeRole: 'memory'
      }, 'schem-memory');
    }
    return id;
  };

  const addAssignEdges = () => {
    const assigns = Array.isArray(raw.assigns) ? raw.assigns : [];
    const maxAssigns = shouldShowChildren && focusNode.children.length > 0 ? 48 : 220;
    for (let idx = 0; idx < Math.min(assigns.length, maxAssigns); idx += 1) {
      const assign = assigns[idx];
      const targetName = String(assign?.target || '').trim();
      if (!targetName) {
        continue;
      }
      const opId = `op:${focusNode.id}:assign:${idx}`;
      pushNode(opId, {
        label: `= ${targetName}`,
        nodeRole: 'op'
      }, 'schem-op');

      const targetRef = resolveNodeSignalRef(focusNode, lookup, targetName, 1, liveSignalSet);
      const targetNetId = ensureNet(targetRef?.name || targetName, targetRef?.width || 1);
      if (targetRef && targetNetId) {
        pushEdge(opId, targetNetId, {
          signalName: targetRef.name,
          liveName: targetRef.liveName || '',
          valueKey: targetRef.valueKey,
          kind: 'assign-target'
        }, 'schem-wire');
      }

      const sourceSignals = Array.from(collectExprSignalNames(assign?.expr, new Set(), 14));
      for (const sourceName of sourceSignals) {
        const sourceRef = resolveNodeSignalRef(focusNode, lookup, sourceName, 1, liveSignalSet);
        const sourceNetId = ensureNet(sourceRef?.name || sourceName, sourceRef?.width || 1);
        if (!sourceRef || !sourceNetId) {
          continue;
        }
        pushEdge(sourceNetId, opId, {
          signalName: sourceRef.name,
          liveName: sourceRef.liveName || '',
          valueKey: sourceRef.valueKey,
          kind: 'assign-source'
        }, 'schem-wire');
      }
    }
  };

  const writePorts = Array.isArray(raw.write_ports) ? raw.write_ports : [];
  for (const [idx, port] of writePorts.entries()) {
    const memId = ensureMemoryNode(port?.memory || `mem_wr_${idx}`);
    if (!memId) {
      continue;
    }
    for (const signalName of [summarizeExpr(port?.addr), summarizeExpr(port?.data), summarizeExpr(port?.enable), port?.clock]) {
      const ref = resolveNodeSignalRef(focusNode, lookup, signalName, 1, liveSignalSet);
      const netId = ensureNet(ref?.name || signalName, 1);
      if (!ref || !netId) {
        continue;
      }
      pushEdge(netId, memId, {
        signalName: ref.name,
        liveName: ref.liveName || '',
        valueKey: ref.valueKey,
        kind: 'mem-write'
      }, 'schem-wire');
    }
  }

  const syncReadPorts = Array.isArray(raw.sync_read_ports) ? raw.sync_read_ports : [];
  for (const [idx, port] of syncReadPorts.entries()) {
    const memId = ensureMemoryNode(port?.memory || `mem_rd_${idx}`);
    if (!memId) {
      continue;
    }
    for (const signalName of [summarizeExpr(port?.addr), summarizeExpr(port?.enable), port?.clock]) {
      const ref = resolveNodeSignalRef(focusNode, lookup, signalName, 1, liveSignalSet);
      const netId = ensureNet(ref?.name || signalName, 1);
      if (!ref || !netId) {
        continue;
      }
      pushEdge(netId, memId, {
        signalName: ref.name,
        liveName: ref.liveName || '',
        valueKey: ref.valueKey,
        kind: 'mem-read-ctrl'
      }, 'schem-wire');
    }
    const dataRef = resolveNodeSignalRef(focusNode, lookup, port?.data, 1, liveSignalSet);
    const dataNetId = ensureNet(dataRef?.name || port?.data, 1);
    if (dataRef && dataNetId) {
      pushEdge(memId, dataNetId, {
        signalName: dataRef.name,
        liveName: dataRef.liveName || '',
        valueKey: dataRef.valueKey,
        kind: 'mem-read-data'
      }, 'schem-wire');
    }
  }

  addAssignEdges();

  return elements;
}

function updateComponentGraphActivity(cy) {
  if (!cy) {
    return;
  }
  const nextValues = new Map();
  const highlight = state.components.graphHighlightedSignal;

  cy.batch(() => {
    cy.nodes('.schem-net, .schem-pin').forEach((node) => {
      const valueKey = String(node.data('valueKey') || '');
      const liveName = String(node.data('liveName') || '');
      const signalName = String(node.data('signalName') || '');
      if (!valueKey) {
        return;
      }
      const value = liveName ? signalLiveValueByName(liveName) : null;
      const valueText = value == null ? '' : toBigInt(value).toString();
      const previous = state.components.graphLiveValues.get(valueKey);
      const toggled = previous !== undefined && previous !== valueText;
      const active = valueText !== '' && valueText !== '0';
      const selected = !!highlight && (
        (!!highlight.liveName && liveName === highlight.liveName)
        || (!!highlight.signalName && signalName === highlight.signalName)
      );

      if (node.hasClass('schem-net')) {
        node.toggleClass('net-active', active);
        node.toggleClass('net-toggled', toggled);
        node.toggleClass('net-selected', selected);
      }
      if (node.hasClass('schem-pin')) {
        node.toggleClass('pin-active', active);
        node.toggleClass('pin-toggled', toggled);
        node.toggleClass('pin-selected', selected);
      }
      nextValues.set(valueKey, valueText);
    });

    cy.edges('.schem-wire').forEach((edge) => {
      const valueKey = String(edge.data('valueKey') || '');
      const signalName = String(edge.data('signalName') || '');
      const liveName = String(edge.data('liveName') || '');
      const valueText = valueKey ? (nextValues.get(valueKey) || '') : '';
      const previous = valueKey ? state.components.graphLiveValues.get(valueKey) : undefined;
      const toggled = valueKey && previous !== undefined && previous !== valueText;
      const active = valueText !== '' && valueText !== '0';

      const highlighted = !!highlight && (
        (!!highlight.liveName && liveName === highlight.liveName)
        || (!!highlight.signalName && signalName === highlight.signalName)
      );

      edge.toggleClass('wire-active', active);
      edge.toggleClass('wire-toggled', !!toggled);
      edge.toggleClass('wire-selected', highlighted);
    });
  });

  state.components.graphLiveValues = nextValues;
}

function elkPortLayoutOptions() {
  return {
    algorithm: 'layered',
    'elk.direction': 'RIGHT',
    'elk.edgeRouting': 'ORTHOGONAL',
    'elk.layered.crossingMinimization.strategy': 'LAYER_SWEEP',
    'elk.layered.nodePlacement.strategy': 'NETWORK_SIMPLEX',
    'elk.layered.nodePlacement.favorStraightEdges': true,
    'elk.layered.considerModelOrder.strategy': 'NODES_AND_EDGES',
    'elk.layered.spacing.nodeNodeBetweenLayers': 170,
    'elk.spacing.nodeNode': 96,
    'elk.spacing.edgeNode': 64,
    'elk.spacing.edgeEdge': 30,
    'elk.padding': '[left=90,top=60,right=90,bottom=60]',
    'elk.separateConnectedComponents': true
  };
}

function toElkPortSide(side) {
  const raw = String(side || '').toLowerCase();
  if (raw === 'left') {
    return 'WEST';
  }
  if (raw === 'right') {
    return 'EAST';
  }
  if (raw === 'top') {
    return 'NORTH';
  }
  if (raw === 'bottom') {
    return 'SOUTH';
  }
  return 'WEST';
}

async function runElkPortLayout(cy) {
  if (!cy || typeof window.ELK !== 'function') {
    state.components.graphLayoutEngine = 'none';
    return;
  }

  const symbolNodes = cy.nodes('.schem-symbol');
  const netNodes = cy.nodes('.schem-net');
  const pinNodes = cy.nodes('.schem-pin');
  const wireEdges = cy.edges('.schem-wire');
  if (symbolNodes.length === 0 && netNodes.length === 0) {
    state.components.graphLayoutEngine = 'none';
    return;
  }

  const pinBySymbol = new Map();
  pinNodes.forEach((pin) => {
    const symbolId = String(pin.data('symbolId') || '').trim();
    if (!symbolId) {
      return;
    }
    if (!pinBySymbol.has(symbolId)) {
      pinBySymbol.set(symbolId, []);
    }
    pinBySymbol.get(symbolId).push(pin);
  });

  const children = [];
  symbolNodes.forEach((symbol) => {
    const symbolId = symbol.id();
    const width = Math.max(92, Number.parseInt(symbol.data('symbolWidth'), 10) || symbol.outerWidth() || 150);
    const height = Math.max(36, Number.parseInt(symbol.data('symbolHeight'), 10) || symbol.outerHeight() || 64);
    const ports = (pinBySymbol.get(symbolId) || []).map((pin) => ({
      id: pin.id(),
      width: Math.max(8, pin.outerWidth() || 12),
      height: Math.max(6, pin.outerHeight() || 8),
      layoutOptions: {
        'elk.port.side': toElkPortSide(pin.data('side')),
        'elk.port.index': String(Number.parseInt(pin.data('order'), 10) || 0)
      }
    }));

    children.push({
      id: symbolId,
      width,
      height,
      ports,
      layoutOptions: {
        'elk.portConstraints': 'FIXED_SIDE'
      }
    });
  });

  netNodes.forEach((net) => {
    const width = Math.max(26, net.outerWidth() || 52);
    const height = Math.max(12, net.outerHeight() || 18);
    children.push({
      id: net.id(),
      width,
      height
    });
  });

  const edges = [];
  wireEdges.forEach((edge) => {
    const source = edge.source();
    const target = edge.target();
    const sourceId = source.id();
    const targetId = target.id();
    if (!sourceId || !targetId) {
      return;
    }
    edges.push({
      id: edge.id(),
      sources: [sourceId],
      targets: [targetId]
    });
  });

  const elk = new window.ELK();
  const graph = {
    id: 'root',
    children,
    edges,
    layoutOptions: elkPortLayoutOptions()
  };

  const laidOut = await elk.layout(graph);
  if (!laidOut || !Array.isArray(laidOut.children)) {
    state.components.graphLayoutEngine = 'none';
    return;
  }
  if (cy !== state.components.graph) {
    return;
  }

  const childById = new Map(laidOut.children.map((entry) => [String(entry.id || ''), entry]));
  cy.batch(() => {
    symbolNodes.forEach((symbol) => {
      const node = childById.get(symbol.id());
      if (!node) {
        return;
      }
      const width = Number(node.width) || Math.max(92, Number.parseInt(symbol.data('symbolWidth'), 10) || symbol.outerWidth() || 150);
      const height = Number(node.height) || Math.max(36, Number.parseInt(symbol.data('symbolHeight'), 10) || symbol.outerHeight() || 64);
      const x = (Number(node.x) || 0) + width * 0.5;
      const y = (Number(node.y) || 0) + height * 0.5;
      symbol.position({ x, y });

      const ports = Array.isArray(node.ports) ? node.ports : [];
      for (const port of ports) {
        const pin = cy.getElementById(String(port.id || ''));
        if (!pin || pin.length === 0) {
          continue;
        }
        const px = (Number(node.x) || 0) + (Number(port.x) || 0) + (Number(port.width) || pin.outerWidth() || 12) * 0.5;
        const py = (Number(node.y) || 0) + (Number(port.y) || 0) + (Number(port.height) || pin.outerHeight() || 8) * 0.5;
        pin.position({ x: px, y: py });
      }
    });

    netNodes.forEach((net) => {
      const node = childById.get(net.id());
      if (!node) {
        return;
      }
      const width = Number(node.width) || net.outerWidth() || 52;
      const height = Number(node.height) || net.outerHeight() || 18;
      const x = (Number(node.x) || 0) + width * 0.5;
      const y = (Number(node.y) || 0) + height * 0.5;
      net.position({ x, y });
    });
  });

  state.components.graphLayoutEngine = 'elk';
  cy.fit(cy.elements(), 26);
}

function ensureComponentGraph(model) {
  if (!dom.componentVisual || !model) {
    return null;
  }
  if (typeof window.cytoscape !== 'function') {
    return null;
  }

  const focusNode = currentComponentGraphFocusNode();
  if (!focusNode) {
    return null;
  }
  const showChildren = !!state.components.graphShowChildren;
  const schematicKey = state.components.schematicBundle
    ? (state.components.schematicBundle.generated_at || state.components.schematicBundle.runner || 'schem')
    : 'none';
  const elkAvailable = typeof window.ELK === 'function';
  state.components.graphElkAvailable = elkAvailable;
  const graphKey = `${state.components.sourceKey}:schematic:${state.theme}:${schematicKey}:${focusNode.id}:${showChildren ? 1 : 0}:${focusNode.children.length}:${focusNode.signals.length}:${elkAvailable ? 1 : 0}`;
  if (!elkAvailable) {
    state.components.graphLayoutEngine = 'missing';
    return null;
  }
  if (state.components.graph && state.components.graphKey === graphKey) {
    return state.components.graph;
  }

  destroyComponentGraph();
  dom.componentVisual.innerHTML = '';

  const palette = state.theme === 'shenzhen'
    ? {
        componentBg: '#1b3d32',
        componentBorder: '#76d4a4',
        componentText: '#d8eee0',
        pinBg: '#2d5d4f',
        pinBorder: '#8bd7b5',
        netBg: '#243a35',
        netBorder: '#527a6d',
        netText: '#b6d2c5',
        ioBg: '#28463d',
        ioBorder: '#7ecdad',
        opBg: '#3f4c3a',
        memoryBg: '#4f3e2f',
        wire: '#4f7d6d',
        wireActive: '#7be9ad',
        wireToggle: '#f4bf66',
        selected: '#9cffe3'
      }
    : {
        componentBg: '#214c71',
        componentBorder: '#2f6b97',
        componentText: '#e7f3ff',
        pinBg: '#35597a',
        pinBorder: '#79bde3',
        netBg: '#223247',
        netBorder: '#3e5f83',
        netText: '#c0d7ef',
        ioBg: '#1f4258',
        ioBorder: '#6eaed4',
        opBg: '#3b4559',
        memoryBg: '#54434e',
        wire: '#3a5f82',
        wireActive: '#3dd7c2',
        wireToggle: '#ffbc5a',
        selected: '#7fdfff'
      };

  const schematicElements = createComponentSchematicElements(model, focusNode, showChildren);
  let cy = null;
  const baseConfig = {
    container: dom.componentVisual,
    elements: schematicElements,
    style: [
      {
        selector: 'node',
        style: {
          'label': 'data(label)',
          'font-size': 8,
          'color': palette.componentText,
          'text-wrap': 'ellipsis',
          'text-max-width': 140,
          'text-halign': 'center',
          'text-valign': 'center',
          'border-width': 1.2
        }
      },
      {
        selector: 'node.schem-symbol',
        style: {
          'shape': 'round-rectangle',
          'width': 'data(symbolWidth)',
          'height': 'data(symbolHeight)',
          'padding-left': 10,
          'padding-right': 10
        }
      },
      {
        selector: 'node.schem-component',
        style: {
          'background-color': palette.componentBg,
          'border-color': palette.componentBorder,
          'border-width': 1.7
        }
      },
      {
        selector: 'node.schem-component-fallback',
        style: {
          'width': 168,
          'height': 64
        }
      },
      {
        selector: 'node.schem-focus',
        style: {
          'border-width': 2.2
        }
      },
      {
        selector: 'node.schem-net',
        style: {
          'shape': 'round-rectangle',
          'background-color': palette.netBg,
          'border-color': palette.netBorder,
          'color': palette.netText,
          'width': 52,
          'height': 18,
          'font-size': 7,
          'text-max-width': 74,
          'padding-left': 4,
          'padding-right': 4
        }
      },
      {
        selector: 'node.schem-net.schem-bus',
        style: {
          'border-width': 2.2
        }
      },
      {
        selector: 'node.schem-net.net-active',
        style: {
          'background-color': palette.wireActive,
          'border-color': palette.wireActive,
          'color': '#001513'
        }
      },
      {
        selector: 'node.schem-net.net-toggled',
        style: {
          'border-color': palette.wireToggle,
          'border-width': 2.2
        }
      },
      {
        selector: 'node.schem-net.net-selected',
        style: {
          'border-color': palette.selected,
          'border-width': 2.8
        }
      },
      {
        selector: 'node.schem-pin',
        style: {
          'shape': 'round-rectangle',
          'label': '',
          'background-color': palette.pinBg,
          'border-color': palette.pinBorder,
          'width': 14,
          'height': 10,
          'border-width': 1.2
        }
      },
      {
        selector: 'node.schem-pin.schem-bus',
        style: {
          'height': 12,
          'border-width': 2.1
        }
      },
      {
        selector: 'node.schem-pin.pin-active',
        style: {
          'background-color': palette.wireActive,
          'border-color': palette.wireActive
        }
      },
      {
        selector: 'node.schem-pin.pin-toggled',
        style: {
          'border-color': palette.wireToggle
        }
      },
      {
        selector: 'node.schem-pin.pin-selected',
        style: {
          'border-color': palette.selected,
          'border-width': 2.4
        }
      },
      {
        selector: 'node.schem-io',
        style: {
          'shape': 'round-rectangle',
          'background-color': palette.ioBg,
          'border-color': palette.ioBorder,
          'width': 34,
          'height': 16,
          'font-size': 6,
          'text-max-width': 56
        }
      },
      {
        selector: 'node.schem-op',
        style: {
          'background-color': palette.opBg,
          'border-color': palette.wire,
          'width': 104,
          'height': 42,
          'font-size': 8
        }
      },
      {
        selector: 'node.schem-memory',
        style: {
          'shape': 'round-rectangle',
          'background-color': palette.memoryBg,
          'border-color': palette.wire,
          'border-style': 'double',
          'width': 124,
          'height': 56,
          'font-size': 8
        }
      },
      {
        selector: 'node.selected',
        style: {
          'border-color': palette.selected,
          'border-width': 2.6
        }
      },
      {
        selector: 'edge',
        style: {
          'width': 1.4,
          'line-color': palette.wire,
          'target-arrow-color': palette.wire,
          'target-arrow-shape': 'none',
          'source-arrow-shape': 'none',
          'curve-style': 'taxi',
          'taxi-direction': 'auto',
          'taxi-turn': 18,
          'opacity': 0.9
        }
      },
      {
        selector: 'edge.schem-bus',
        style: {
          'width': 2.4
        }
      },
      {
        selector: 'edge.schem-bidir',
        style: {
          'line-style': 'dashed'
        }
      },
      {
        selector: 'edge.wire-active',
        style: {
          'line-color': palette.wireActive,
          'target-arrow-color': palette.wireActive,
          'source-arrow-color': palette.wireActive,
          'width': 2
        }
      },
      {
        selector: 'edge.wire-toggled',
        style: {
          'line-color': palette.wireToggle,
          'target-arrow-color': palette.wireToggle,
          'source-arrow-color': palette.wireToggle,
          'width': 2.7
        }
      },
      {
        selector: 'edge.wire-selected',
        style: {
          'line-color': '#ffffff',
          'target-arrow-color': '#ffffff',
          'source-arrow-color': '#ffffff',
          'width': 3.2
        }
      }
    ],
    layout: {
      name: 'preset',
      fit: false
    },
    wheelSensitivity: 0.2,
    autoungrabify: true,
    boxSelectionEnabled: false
  };
  cy = window.cytoscape(baseConfig);
  state.components.graphLayoutEngine = 'elk';
  runElkPortLayout(cy).catch((_err) => {
    state.components.graphLayoutEngine = 'error';
  });

  cy.on('tap', 'node', (evt) => {
    const target = evt?.target;
    if (!target) {
      return;
    }
    const componentId = String(target.data('componentId') || '').trim();
    const nodeRole = String(target.data('nodeRole') || '');

    if (!componentId || !model.nodes.has(componentId)) {
      if (nodeRole === 'net' || nodeRole === 'pin') {
        const signalName = String(target.data('signalName') || '').trim();
        const liveName = String(target.data('liveName') || '').trim();
        state.components.graphHighlightedSignal = signalName || liveName
          ? { signalName: signalName || null, liveName: liveName || null }
          : null;
        renderComponentGraphPanel();
      }
      return;
    }

    const now = Date.now();
    const lastTap = state.components.graphLastTap;
    const isDoubleTap = !!(lastTap && lastTap.nodeId === componentId && (now - lastTap.timeMs) < 320);
    state.components.graphLastTap = { nodeId: componentId, timeMs: now };

    if (state.components.selectedNodeId !== componentId) {
      state.components.selectedNodeId = componentId;
      renderComponentTree();
    }
    if (isDoubleTap) {
      state.components.graphFocusId = componentId;
      state.components.graphShowChildren = true;
      state.components.graphHighlightedSignal = null;
    }
    renderComponentViews();
  });

  cy.on('tap', 'edge', (evt) => {
    const target = evt?.target;
    if (!target) {
      return;
    }
    const signalName = String(target.data('signalName') || '').trim();
    const liveName = String(target.data('liveName') || '').trim();
    state.components.graphHighlightedSignal = signalName || liveName
      ? { signalName: signalName || null, liveName: liveName || null }
      : null;
    renderComponentGraphPanel();
  });

  cy.on('tap', (evt) => {
    if (evt?.target === cy) {
      state.components.graphHighlightedSignal = null;
      renderComponentGraphPanel();
    }
  });

  state.components.graph = cy;
  state.components.graphKey = graphKey;
  state.components.graphSelectedId = null;
  return cy;
}

function renderComponentVisual(node) {
  if (!dom.componentVisual) {
    return;
  }
  if (!node || !state.components.model) {
    destroyComponentGraph();
    dom.componentVisual.textContent = 'Select a component to visualize.';
    return;
  }
  if (typeof window.cytoscape !== 'function') {
    destroyComponentGraph();
    dom.componentVisual.textContent = 'Cytoscape not available.';
    return;
  }

  const cy = ensureComponentGraph(state.components.model);
  if (!cy) {
    if (state.components.graphLayoutEngine === 'missing') {
      dom.componentVisual.textContent = 'ELK layout engine unavailable.';
    } else {
      dom.componentVisual.textContent = 'Unable to render component schematic.';
    }
    return;
  }

  if (dom.componentVisual.clientWidth < 20 || dom.componentVisual.clientHeight < 20) {
    requestAnimationFrame(() => {
      if (state.activeTab === 'componentGraphTab') {
        renderComponentGraphPanel();
      }
    });
    return;
  }

  const focusNode = currentComponentGraphFocusNode();
  const findGraphNodeByComponentId = (componentId) => {
    if (!componentId) {
      return null;
    }
    const matches = cy.nodes('.schem-component').filter((entry) => String(entry.data('componentId') || '') === String(componentId));
    return matches && matches.length > 0 ? matches[0] : null;
  };
  const selectedComponentId = (() => {
    if (!node) {
      return focusNode?.id || null;
    }
    const selected = findGraphNodeByComponentId(node.id);
    if (selected) {
      return node.id;
    }
    return focusNode?.id || node.id;
  })();
  const selectedNode = selectedComponentId ? findGraphNodeByComponentId(selectedComponentId) : null;
  const selectedCyId = selectedNode ? selectedNode.id() : null;

  cy.batch(() => {
    cy.nodes('.schem-component').removeClass('selected');
    if (selectedNode) {
      selectedNode.addClass('selected');
    }
  });

  if (state.components.graphSelectedId !== selectedCyId) {
    state.components.graphSelectedId = selectedCyId;
    if (selectedNode) {
      cy.animate({
        center: {
          eles: selectedNode
        }
      }, {
        duration: 180
      });
    }
  } else {
    cy.resize();
  }

  updateComponentGraphActivity(cy);
}

function renderComponentLiveSignals(node) {
  if (!dom.componentLiveSignals) {
    return;
  }
  dom.componentLiveSignals.innerHTML = '';

  if (!node || node.signals.length === 0) {
    dom.componentLiveSignals.textContent = 'No live signals to display.';
    return;
  }

  const highlight = state.components.graphHighlightedSignal;
  let highlightedRows = 0;
  const signals = node.signals.slice(0, 120);
  for (const signal of signals) {
    const row = document.createElement('div');
    row.className = 'component-live-row';
    const matchesHighlight = !!highlight && (
      (!!highlight.liveName && (signal.liveName === highlight.liveName || signal.fullName === highlight.liveName))
      || (!!highlight.signalName && (signal.name === highlight.signalName || signal.fullName === highlight.signalName))
    );
    if (matchesHighlight) {
      row.classList.add('highlight');
      highlightedRows += 1;
    }

    const name = document.createElement('span');
    name.className = 'component-live-name';
    name.textContent = signal.fullName || signal.name;

    const value = document.createElement('span');
    value.className = 'component-live-value';
    const live = signalLiveValue(signal);
    value.textContent = live == null ? '-' : formatValue(live, signal.width || 1);

    row.appendChild(name);
    row.appendChild(value);
    dom.componentLiveSignals.appendChild(row);
  }

  if (highlight && highlightedRows === 0) {
    const row = document.createElement('div');
    row.className = 'component-live-row';
    const name = document.createElement('span');
    name.className = 'component-live-name';
    name.textContent = `Highlighted wire not in ${node.name}`;
    const value = document.createElement('span');
    value.className = 'component-live-value';
    value.textContent = '-';
    row.appendChild(name);
    row.appendChild(value);
    dom.componentLiveSignals.appendChild(row);
  }

  if (node.signals.length > signals.length) {
    const row = document.createElement('div');
    row.className = 'component-live-row';
    const name = document.createElement('span');
    name.className = 'component-live-name';
    name.textContent = `${node.signals.length - signals.length} additional signals`;
    const value = document.createElement('span');
    value.className = 'component-live-value';
    value.textContent = '...';
    row.appendChild(name);
    row.appendChild(value);
    dom.componentLiveSignals.appendChild(row);
  }
}

function ellipsizeText(value, maxLen = 88) {
  const text = String(value ?? '');
  if (text.length <= maxLen) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLen - 3))}...`;
}

function summarizeExpr(expr) {
  if (expr == null) {
    return '-';
  }
  if (typeof expr === 'string' || typeof expr === 'number' || typeof expr === 'bigint' || typeof expr === 'boolean') {
    return String(expr);
  }
  if (Array.isArray(expr)) {
    const preview = expr.slice(0, 3).map((entry) => summarizeExpr(entry)).join(', ');
    return `[${preview}${expr.length > 3 ? ', ...' : ''}]`;
  }
  if (typeof expr !== 'object') {
    return String(expr);
  }

  if (typeof expr.name === 'string') {
    return expr.name;
  }
  if (expr.op && expr.left !== undefined && expr.right !== undefined) {
    return `${summarizeExpr(expr.left)} ${expr.op} ${summarizeExpr(expr.right)}`;
  }
  if (expr.op && expr.operand !== undefined) {
    return `${expr.op} ${summarizeExpr(expr.operand)}`;
  }
  if (expr.value !== undefined && expr.width !== undefined) {
    return `lit(${expr.value}:${expr.width})`;
  }
  if (expr.selector !== undefined && expr.cases !== undefined) {
    return `mux(${summarizeExpr(expr.selector)})`;
  }
  if (expr.kind) {
    return String(expr.kind);
  }
  return JSON.stringify(summarizeIrEntry(expr));
}

function collectConnectionRows(node) {
  const rows = [];

  const schematicEntry = findComponentSchematicEntry(node);
  const schematic = schematicEntry?.schematic;
  if (schematic && typeof schematic === 'object') {
    const symbols = Array.isArray(schematic.symbols) ? schematic.symbols : [];
    const pins = Array.isArray(schematic.pins) ? schematic.pins : [];
    const nets = Array.isArray(schematic.nets) ? schematic.nets : [];
    const wires = Array.isArray(schematic.wires) ? schematic.wires : [];
    if (wires.length > 0) {
      const symbolById = new Map(symbols.map((entry) => [String(entry?.id || ''), entry]).filter(([id]) => !!id));
      const pinById = new Map(pins.map((entry) => [String(entry?.id || ''), entry]).filter(([id]) => !!id));
      const netById = new Map(nets.map((entry) => [String(entry?.id || ''), entry]).filter(([id]) => !!id));

      const pinLabel = (pinId) => {
        const pin = pinById.get(String(pinId || ''));
        if (!pin) {
          return String(pinId || '?');
        }
        const symbol = symbolById.get(String(pin.symbol_id || ''));
        const symbolName = String(symbol?.label || symbol?.id || pin.symbol_id || '?');
        const pinName = String(pin.name || pin.signal || pin.id || '?');
        return `${symbolName}.${pinName}`;
      };

      for (const wire of wires) {
        if (!wire || typeof wire !== 'object') {
          continue;
        }
        const fromPinId = String(wire.from_pin_id || '').trim();
        const toPinId = String(wire.to_pin_id || '').trim();
        if (!fromPinId || !toPinId) {
          continue;
        }
        const net = netById.get(String(wire.net_id || '').trim());
        const netName = String(net?.name || wire.signal || '?');
        const width = Number.parseInt(wire.width || net?.width, 10) || 1;
        const direction = String(wire.direction || '?').toLowerCase();
        rows.push({
          type: String(wire.kind || 'wire'),
          source: pinLabel(fromPinId),
          target: pinLabel(toPinId),
          details: `net=${netName} dir=${direction} w=${width}`
        });
      }
      return rows;
    }
  }

  const raw = node?.rawRef;
  if (!raw || typeof raw !== 'object') {
    return rows;
  }

  const instances = Array.isArray(raw.instances) ? raw.instances : [];
  for (const inst of instances) {
    const instanceName = deriveComponentName(inst, 'instance');
    const connections = Array.isArray(inst.connections) ? inst.connections : [];
    for (const conn of connections) {
      rows.push({
        type: 'port',
        source: `${instanceName}.${conn.port_name || conn.port || '?'}`,
        target: String(conn.signal || '?'),
        details: String(conn.direction || '?')
      });
    }
  }

  const children = Array.isArray(raw.children) ? raw.children : [];
  for (const child of children) {
    const instanceName = deriveComponentName(child, 'child');
    const ports = Array.isArray(child?.ports) ? child.ports : [];
    for (const port of ports) {
      if (!port || typeof port.name !== 'string') {
        continue;
      }
      const direction = String(port.direction || '?').toLowerCase();
      if (direction === 'out') {
        rows.push({
          type: 'child-port',
          source: `${instanceName}.${port.name}`,
          target: port.name,
          details: direction
        });
      } else {
        rows.push({
          type: 'child-port',
          source: port.name,
          target: `${instanceName}.${port.name}`,
          details: direction
        });
      }
    }
  }

  const assigns = Array.isArray(raw.assigns) ? raw.assigns : [];
  for (const assign of assigns) {
    rows.push({
      type: 'wire',
      source: summarizeExpr(assign?.expr),
      target: String(assign?.target || '?'),
      details: 'assign'
    });
  }

  const writePorts = Array.isArray(raw.write_ports) ? raw.write_ports : [];
  for (const port of writePorts) {
    rows.push({
      type: 'mem-wr',
      source: summarizeExpr(port?.data),
      target: `${port?.memory || '?'}[${summarizeExpr(port?.addr)}]`,
      details: `clk=${port?.clock || '?'} en=${summarizeExpr(port?.enable)}`
    });
  }

  const syncReadPorts = Array.isArray(raw.sync_read_ports) ? raw.sync_read_ports : [];
  for (const port of syncReadPorts) {
    rows.push({
      type: 'mem-rd',
      source: `${port?.memory || '?'}[${summarizeExpr(port?.addr)}]`,
      target: String(port?.data || '?'),
      details: `clk=${port?.clock || '?'} en=${summarizeExpr(port?.enable)}`
    });
  }

  return rows;
}

function renderComponentConnections(node) {
  if (!dom.componentConnectionMeta || !dom.componentConnectionBody) {
    return;
  }
  dom.componentConnectionBody.innerHTML = '';

  if (!node) {
    dom.componentConnectionMeta.textContent = state.components.parseError || 'Select a component to inspect connections.';
    return;
  }

  const rows = collectConnectionRows(node);
  dom.componentConnectionMeta.textContent = `${rows.length} connections in ${nodeDisplayPath(node)}`;
  if (rows.length === 0) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 4;
    td.textContent = 'No explicit wire/port connections available for this component.';
    tr.appendChild(td);
    dom.componentConnectionBody.appendChild(tr);
    return;
  }

  const maxRows = 420;
  for (const row of rows.slice(0, maxRows)) {
    const tr = document.createElement('tr');

    const tdType = document.createElement('td');
    tdType.textContent = row.type;
    tr.appendChild(tdType);

    const tdSource = document.createElement('td');
    tdSource.textContent = ellipsizeText(row.source);
    tdSource.title = row.source;
    tr.appendChild(tdSource);

    const tdTarget = document.createElement('td');
    tdTarget.textContent = ellipsizeText(row.target);
    tdTarget.title = row.target;
    tr.appendChild(tdTarget);

    const tdDetails = document.createElement('td');
    tdDetails.textContent = ellipsizeText(row.details);
    tdDetails.title = row.details;
    tr.appendChild(tdDetails);

    dom.componentConnectionBody.appendChild(tr);
  }

  if (rows.length > maxRows) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 4;
    td.textContent = `... ${rows.length - maxRows} additional connections not shown`;
    tr.appendChild(td);
    dom.componentConnectionBody.appendChild(tr);
  }
}

function renderComponentInspector() {
  if (!dom.componentTitle || !dom.componentMeta || !dom.componentSignalBody || !dom.componentCode) {
    return;
  }
  renderComponentCodeViewButtons();

  const node = currentSelectedComponentNode();
  if (!node) {
    dom.componentTitle.textContent = 'Component Details';
    dom.componentMeta.textContent = state.components.parseError || 'Load IR to inspect components.';
    if (dom.componentSignalMeta) {
      dom.componentSignalMeta.textContent = state.components.parseError || '';
    }
    dom.componentSignalBody.innerHTML = '';
    dom.componentCode.textContent = 'Select a component to view details.';
    return;
  }

  dom.componentTitle.textContent = nodeDisplayPath(node);
  dom.componentMeta.textContent = `kind=${node.kind} | children=${node.children.length} | signals=${node.signals.length}`;
  if (dom.componentSignalMeta) {
    const shown = Math.min(node.signals.length, COMPONENT_SIGNAL_PREVIEW_LIMIT);
    dom.componentSignalMeta.textContent = `showing ${shown}/${node.signals.length} signals`;
  }

  dom.componentSignalBody.innerHTML = '';
  const rows = node.signals.slice(0, COMPONENT_SIGNAL_PREVIEW_LIMIT);
  for (const signal of rows) {
    const tr = document.createElement('tr');

    const tdName = document.createElement('td');
    tdName.textContent = signal.fullName || signal.name;
    tr.appendChild(tdName);

    const tdWidth = document.createElement('td');
    tdWidth.textContent = String(signal.width || 1);
    tr.appendChild(tdWidth);

    const tdValue = document.createElement('td');
    const value = signalLiveValue(signal);
    tdValue.textContent = value == null ? '-' : formatValue(value, signal.width || 1);
    tr.appendChild(tdValue);

    dom.componentSignalBody.appendChild(tr);
  }

  if (node.signals.length > COMPONENT_SIGNAL_PREVIEW_LIMIT) {
    const tr = document.createElement('tr');
    const td = document.createElement('td');
    td.colSpan = 3;
    td.textContent = `... ${node.signals.length - COMPONENT_SIGNAL_PREVIEW_LIMIT} additional signals not shown`;
    tr.appendChild(td);
    dom.componentSignalBody.appendChild(tr);
  }

  dom.componentCode.textContent = formatComponentCode(node);
}

function renderComponentGraphPanel() {
  const selectedNode = currentSelectedComponentNode();
  const focusNode = currentComponentGraphFocusNode();
  if (!selectedNode || !focusNode) {
    if (dom.componentGraphTitle) {
      dom.componentGraphTitle.textContent = 'Component Schematic';
    }
    if (dom.componentGraphMeta) {
      dom.componentGraphMeta.textContent = state.components.parseError || 'Load IR to inspect component connectivity.';
    }
    if (dom.componentGraphFocusPath) {
      dom.componentGraphFocusPath.textContent = 'Focus: top';
    }
    if (dom.componentGraphTopBtn) {
      dom.componentGraphTopBtn.disabled = true;
    }
    if (dom.componentGraphUpBtn) {
      dom.componentGraphUpBtn.disabled = true;
    }
    renderComponentVisual(null);
    renderComponentLiveSignals(null);
    renderComponentConnections(null);
    return;
  }

  const activeNode = focusNode;

  if (dom.componentGraphTitle) {
    dom.componentGraphTitle.textContent = nodeDisplayPath(activeNode);
  }
  if (dom.componentGraphMeta) {
    const mode = state.components.graphShowChildren ? 'schematic view' : 'symbol view';
    const layout = state.components.graphLayoutEngine || 'none';
    const elk = state.components.graphElkAvailable ? 'ready' : 'missing';
    dom.componentGraphMeta.textContent = `selected=${nodeDisplayPath(selectedNode)} | focus=${nodeDisplayPath(focusNode)} | ${mode} | layout=${layout} | elk=${elk} | dbl-click component to dive`;
  }
  if (dom.componentGraphFocusPath) {
    dom.componentGraphFocusPath.textContent = `Focus: ${nodeDisplayPath(focusNode)}`;
  }
  if (dom.componentGraphTopBtn) {
    const model = state.components.model;
    dom.componentGraphTopBtn.disabled = !model || focusNode.id === model.rootId;
  }
  if (dom.componentGraphUpBtn) {
    dom.componentGraphUpBtn.disabled = !focusNode.parentId;
  }
  renderComponentVisual(selectedNode);
  renderComponentLiveSignals(activeNode);
  renderComponentConnections(focusNode);
}

function parseComponentMetaFromCurrentIr() {
  const source = currentComponentSourceText().trim();
  const sourceKey = currentIrSourceKey(source);
  if (!source) {
    state.components.model = null;
    state.components.sourceKey = sourceKey;
    state.components.parseError = 'No IR loaded.';
    state.components.selectedNodeId = null;
    state.components.graphFocusId = null;
    state.components.graphShowChildren = false;
    state.components.graphLastTap = null;
    state.components.graphHighlightedSignal = null;
    state.components.graphLiveValues = new Map();
    return;
  }
  if (state.components.sourceKey === sourceKey && state.components.model) {
    return;
  }

  try {
    const meta = parseIrMeta(source);
    state.components.model = buildComponentModel(meta);
    state.components.sourceKey = sourceKey;
    state.components.parseError = '';
    state.components.graphHighlightedSignal = null;
    state.components.graphLiveValues = new Map();
    ensureComponentSelection();
    ensureComponentGraphFocus();
  } catch (err) {
    state.components.model = null;
    state.components.sourceKey = sourceKey;
    state.components.parseError = `Component explorer parse failed: ${err.message || err}`;
    state.components.selectedNodeId = null;
    state.components.graphFocusId = null;
    state.components.graphShowChildren = false;
    state.components.graphLastTap = null;
    state.components.graphHighlightedSignal = null;
    state.components.graphLiveValues = new Map();
  }
}

function rebuildComponentExplorer(meta = state.irMeta, source = currentComponentSourceText()) {
  const sourceKey = currentIrSourceKey(source);
  if (!meta?.ir) {
    parseComponentMetaFromCurrentIr();
    renderComponentTree();
    renderComponentViews();
    return;
  }

  state.components.model = buildComponentModel(meta);
  state.components.sourceKey = sourceKey;
  state.components.parseError = '';
  state.components.graphHighlightedSignal = null;
  state.components.graphLiveValues = new Map();
  ensureComponentSelection();
  ensureComponentGraphFocus();
  renderComponentTree();
  renderComponentViews();
}

function refreshComponentExplorer() {
  const source = currentComponentSourceText();
  const sourceKey = currentIrSourceKey(source);
  const preferredMeta = state.components.overrideMeta || state.irMeta;
  if (preferredMeta?.ir) {
    if (!state.components.model || state.components.sourceKey !== sourceKey) {
      rebuildComponentExplorer(preferredMeta, source);
    }
  } else {
    parseComponentMetaFromCurrentIr();
  }
  ensureComponentSelection();
  ensureComponentGraphFocus();
  renderComponentTree();
  renderComponentViews();
}

function parseHexOrDec(text, defaultValue = 0) {
  const raw = String(text || '').trim().toLowerCase();
  if (!raw) {
    return defaultValue;
  }
  if (raw.startsWith('0x')) {
    const value = Number.parseInt(raw.slice(2), 16);
    return Number.isFinite(value) ? value : defaultValue;
  }
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) ? value : defaultValue;
}

function hexWord(value) {
  return (Number(value) & 0xffff).toString(16).toUpperCase().padStart(4, '0');
}

function hexByte(value) {
  return value.toString(16).toUpperCase().padStart(2, '0');
}

function isApple2UiEnabled() {
  return state.apple2.enabled && state.sim?.apple2_mode?.();
}

function updateIoToggleUi() {
  const active = isApple2UiEnabled();
  if (dom.toggleHires) {
    dom.toggleHires.checked = !!state.apple2.displayHires;
    dom.toggleHires.disabled = !active;
  }
  if (dom.toggleColor) {
    dom.toggleColor.checked = !!state.apple2.displayColor;
    dom.toggleColor.disabled = !active || !state.apple2.displayHires;
  }
  if (dom.toggleSound) {
    dom.toggleSound.checked = !!state.apple2.soundEnabled;
    dom.toggleSound.disabled = !active;
  }
  if (dom.apple2TextScreen) {
    dom.apple2TextScreen.hidden = active && state.apple2.displayHires;
  }
  if (dom.apple2HiresCanvas) {
    dom.apple2HiresCanvas.hidden = !(active && state.apple2.displayHires);
  }
}

function apple2HiresLineAddress(row) {
  const section = Math.floor(row / 64);
  const rowInSection = row % 64;
  const group = Math.floor(rowInSection / 8);
  const lineInGroup = rowInSection % 8;
  return 0x2000 + (lineInGroup * 0x400) + (group * 0x80) + (section * 0x28);
}

function ensureApple2AudioGraph() {
  if (state.apple2.audioCtx && state.apple2.audioOsc && state.apple2.audioGain) {
    return true;
  }

  const AudioCtx = window.AudioContext || window.webkitAudioContext;
  if (!AudioCtx) {
    return false;
  }

  const ctx = new AudioCtx();
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();

  osc.type = 'square';
  osc.frequency.value = 440;
  gain.gain.value = 0;

  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();

  state.apple2.audioCtx = ctx;
  state.apple2.audioOsc = osc;
  state.apple2.audioGain = gain;
  return true;
}

async function setApple2SoundEnabled(enabled) {
  state.apple2.soundEnabled = !!enabled;
  updateIoToggleUi();

  if (!state.apple2.soundEnabled) {
    if (state.apple2.audioCtx && state.apple2.audioGain) {
      state.apple2.audioGain.gain.setTargetAtTime(0, state.apple2.audioCtx.currentTime, 0.01);
    }
    return;
  }

  if (!ensureApple2AudioGraph()) {
    state.apple2.soundEnabled = false;
    updateIoToggleUi();
    log('WebAudio unavailable: SOUND toggle disabled');
    return;
  }

  try {
    await state.apple2.audioCtx.resume();
  } catch (err) {
    state.apple2.soundEnabled = false;
    updateIoToggleUi();
    log(`Failed to enable audio: ${err.message || err}`);
  }
}

function updateApple2SpeakerAudio(toggles, cyclesRun) {
  if (!state.apple2.soundEnabled) {
    return;
  }
  if (!state.apple2.audioCtx || !state.apple2.audioOsc || !state.apple2.audioGain) {
    return;
  }

  const ctx = state.apple2.audioCtx;
  const gain = state.apple2.audioGain.gain;
  const freq = state.apple2.audioOsc.frequency;

  if (!toggles || !cyclesRun) {
    gain.setTargetAtTime(0, ctx.currentTime, 0.012);
    return;
  }

  const hz = (toggles * 1_000_000) / (2 * Math.max(1, cyclesRun));
  const clampedHz = Math.max(40, Math.min(6000, hz));
  freq.setTargetAtTime(clampedHz, ctx.currentTime, 0.006);
  gain.setTargetAtTime(0.03, ctx.currentTime, 0.005);
}

function setMemoryDumpStatus(message) {
  if (dom.memoryDumpStatus) {
    dom.memoryDumpStatus.textContent = message || '';
  }
}

function setMemoryResetVectorInput(value) {
  if (!dom.memoryResetVector) {
    return;
  }
  const parsed = parsePcLiteral(value);
  dom.memoryResetVector.value = parsed == null ? '' : `0x${hexWord(parsed)}`;
}

function bytesToBase64(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return '';
  }
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function base64ToBytes(base64) {
  const binary = atob(base64 || '');
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    out[i] = binary.charCodeAt(i);
  }
  return out;
}

function parsePcLiteral(value) {
  if (value == null) {
    return null;
  }
  if (Number.isFinite(value)) {
    return Math.trunc(value) & 0xffff;
  }
  const raw = String(value).trim();
  if (!raw) {
    return null;
  }

  let m = raw.match(/^\$([0-9A-Fa-f]{1,4})$/);
  if (m) {
    return Number.parseInt(m[1], 16) & 0xffff;
  }
  m = raw.match(/^0x([0-9A-Fa-f]{1,4})$/i);
  if (m) {
    return Number.parseInt(m[1], 16) & 0xffff;
  }
  m = raw.match(/^[0-9A-Fa-f]{1,4}$/);
  if (m && /[A-Fa-f]/.test(raw)) {
    return Number.parseInt(raw, 16) & 0xffff;
  }
  m = raw.match(/^[0-9]{1,5}$/);
  if (m) {
    return Number.parseInt(m[0], 10) & 0xffff;
  }
  return null;
}

function extractPcFromText(text) {
  if (typeof text !== 'string' || !text.trim()) {
    return null;
  }
  const patterns = [
    /PC at dump:\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})/i,
    /start[_\s-]*pc\s*[:=]\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})/i,
    /\(PC\s*=\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})\)/i,
    /\bPC\s*[:=]\s*(\$[0-9A-Fa-f]{1,4}|0x[0-9A-Fa-f]{1,4}|[0-9]{1,5})/i
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) {
      continue;
    }
    const parsed = parsePcLiteral(match[1]);
    if (parsed != null) {
      return parsed;
    }
  }
  return null;
}

function isSnapshotFileName(fileName) {
  const lower = String(fileName || '').trim().toLowerCase();
  return (
    lower.endsWith('.rhdlsnap')
    || lower.endsWith('.rhdlsnap.json')
    || lower.endsWith('.snapshot')
    || lower.endsWith('.snapshot.json')
  );
}

function buildApple2SnapshotPayload(bytes, offset = 0, label = 'saved dump', savedAtIso = null, startPc = null) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return null;
  }

  const dataB64 = bytesToBase64(bytes);
  if (!dataB64) {
    return null;
  }

  const iso = typeof savedAtIso === 'string' && savedAtIso ? savedAtIso : new Date().toISOString();
  const payload = {
    kind: APPLE2_SNAPSHOT_KIND,
    version: APPLE2_SNAPSHOT_VERSION,
    label: String(label || 'saved dump'),
    offset: Math.max(0, Number.parseInt(offset, 10) || 0),
    length: bytes.length,
    savedAtMs: Date.now(),
    savedAtIso: iso,
    dataB64
  };

  const parsedPc = parsePcLiteral(startPc);
  if (parsedPc != null) {
    payload.startPc = parsedPc;
  }

  return payload;
}

function parseApple2SnapshotPayload(payload) {
  if (!payload || typeof payload !== 'object') {
    return null;
  }

  if (payload.kind != null && payload.kind !== APPLE2_SNAPSHOT_KIND) {
    return null;
  }
  if (payload.version != null) {
    const version = Number.parseInt(payload.version, 10);
    if (!Number.isFinite(version) || version > APPLE2_SNAPSHOT_VERSION) {
      return null;
    }
  }
  if (typeof payload.dataB64 !== 'string') {
    return null;
  }

  let bytes;
  try {
    bytes = base64ToBytes(payload.dataB64);
  } catch (_err) {
    return null;
  }
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return null;
  }

  let startPc = null;
  const pcCandidates = [
    payload.startPc,
    payload.start_pc,
    payload.pc,
    payload.resetPc,
    payload.reset_pc,
    payload.entryPc,
    payload.entry_pc
  ];
  for (const candidate of pcCandidates) {
    const parsed = parsePcLiteral(candidate);
    if (parsed != null) {
      startPc = parsed;
      break;
    }
  }
  if (startPc == null) {
    startPc = extractPcFromText(payload.label) ?? extractPcFromText(payload.notes);
  }

  return {
    bytes,
    offset: Math.max(0, Number.parseInt(payload.offset, 10) || 0),
    label: typeof payload.label === 'string' && payload.label ? payload.label : 'saved dump',
    savedAtIso: typeof payload.savedAtIso === 'string' ? payload.savedAtIso : null,
    startPc
  };
}

function parseApple2SnapshotText(text) {
  if (typeof text !== 'string' || !text.trim()) {
    return null;
  }
  try {
    const payload = JSON.parse(text);
    return parseApple2SnapshotPayload(payload);
  } catch (_err) {
    return null;
  }
}

function saveLastMemoryDumpToStorage(bytes, offset = 0, label = 'saved dump', savedAtIso = null, startPc = null) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return false;
  }
  try {
    const payload = buildApple2SnapshotPayload(bytes, offset, label, savedAtIso, startPc);
    if (!payload) {
      return false;
    }
    window.localStorage.setItem(LAST_APPLE2_DUMP_KEY, JSON.stringify(payload));
    return true;
  } catch (err) {
    log(`Could not persist last memory dump: ${err.message || err}`);
    return false;
  }
}

function loadLastMemoryDumpFromStorage() {
  try {
    const raw = window.localStorage.getItem(LAST_APPLE2_DUMP_KEY);
    if (!raw) {
      return null;
    }
    return parseApple2SnapshotPayload(JSON.parse(raw));
  } catch (err) {
    log(`Could not read last memory dump: ${err.message || err}`);
    return null;
  }
}

function triggerDownload(blob, filename) {
  if (!blob || !filename) {
    return;
  }
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function downloadMemoryDump(bytes, filename) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return;
  }
  triggerDownload(new Blob([bytes], { type: 'application/octet-stream' }), filename);
}

function downloadApple2Snapshot(snapshot, filename) {
  if (!snapshot || typeof snapshot !== 'object') {
    return;
  }
  const encoded = JSON.stringify(snapshot, null, 2);
  triggerDownload(new Blob([encoded], { type: 'application/json' }), filename);
}

async function saveApple2MemoryDump() {
  if (!state.sim || !isApple2UiEnabled()) {
    setMemoryDumpStatus('Load the Apple II runner first.');
    return false;
  }

  const bytes = state.sim.apple2_read_ram(0, APPLE2_RAM_BYTES);
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    setMemoryDumpStatus('Save failed: RAM read returned no data.');
    return false;
  }

  const now = new Date();
  const nowIso = now.toISOString();
  const startPc = getApple2ProgramCounter();
  const stamp = nowIso.replace(/[:.]/g, '-');
  const filename = `apple2_dump_${stamp}.bin`;
  downloadMemoryDump(bytes, filename);

  state.memory.lastSavedDump = {
    bytes: new Uint8Array(bytes),
    offset: 0,
    label: `apple2 ram snapshot ${nowIso}`,
    savedAtIso: nowIso,
    startPc
  };

  const persisted = saveLastMemoryDumpToStorage(bytes, 0, `apple2 ram snapshot ${nowIso}`, nowIso, startPc);
  const msg = persisted
    ? `Saved dump ${filename} (${bytes.length} bytes). Last dump updated.`
    : `Saved dump ${filename} (${bytes.length} bytes). Could not update last saved dump.`;
  setMemoryDumpStatus(msg);
  log(msg);
  return true;
}

async function saveApple2MemorySnapshot() {
  if (!state.sim || !isApple2UiEnabled()) {
    setMemoryDumpStatus('Load the Apple II runner first.');
    return false;
  }

  const bytes = state.sim.apple2_read_ram(0, APPLE2_RAM_BYTES);
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    setMemoryDumpStatus('Snapshot failed: RAM read returned no data.');
    return false;
  }

  const nowIso = new Date().toISOString();
  const startPc = getApple2ProgramCounter();
  const label = `apple2 ram snapshot ${nowIso}`;
  const snapshot = buildApple2SnapshotPayload(bytes, 0, label, nowIso, startPc);
  if (!snapshot) {
    setMemoryDumpStatus('Snapshot failed: could not encode payload.');
    return false;
  }

  const stamp = nowIso.replace(/[:.]/g, '-');
  const filename = `apple2_snapshot_${stamp}.rhdlsnap`;
  downloadApple2Snapshot(snapshot, filename);

  state.memory.lastSavedDump = {
    bytes: new Uint8Array(bytes),
    offset: 0,
    label,
    savedAtIso: nowIso,
    startPc
  };

  const persisted = saveLastMemoryDumpToStorage(bytes, 0, label, nowIso, startPc);
  const msg = persisted
    ? `Downloaded snapshot ${filename} (${bytes.length} bytes). Last dump updated.`
    : `Downloaded snapshot ${filename} (${bytes.length} bytes). Could not update last saved dump.`;
  setMemoryDumpStatus(msg);
  log(msg);
  return true;
}

async function loadApple2DumpOrSnapshotFile(file, offsetRaw) {
  if (!file) {
    setMemoryDumpStatus('Select a dump/snapshot file first.');
    return false;
  }

  if (isSnapshotFileName(file.name)) {
    const snapshot = parseApple2SnapshotText(await file.text());
    if (!snapshot) {
      setMemoryDumpStatus(`Invalid snapshot file: ${file.name}`);
      return false;
    }
    if (dom.memoryDumpOffset) {
      dom.memoryDumpOffset.value = `0x${hexWord(snapshot.offset)}`;
    }

    let pcStatus = null;
    let resetAfterLoad = false;
    if (snapshot.startPc != null) {
      pcStatus = await applyApple2SnapshotStartPc(snapshot.startPc);
      resetAfterLoad = !!pcStatus.applied;
      if (pcStatus?.pc != null) {
        setMemoryResetVectorInput(pcStatus.pc);
      }
    }

    const suffix = snapshot.savedAtIso ? ` @ ${snapshot.savedAtIso}` : '';
    const pcSuffix = pcStatus?.pc != null ? ` (PC=$${hexWord(pcStatus.pc)})` : '';
    const loaded = await loadApple2MemoryDumpBytes(snapshot.bytes, snapshot.offset, {
      label: `${snapshot.label}${suffix}${pcSuffix}`,
      resetAfterLoad
    });

    if (loaded && pcStatus && !pcStatus.applied) {
      const warn = `Snapshot requested PC=$${hexWord(pcStatus.pc)} but could not apply it (${pcStatus.reason}).`;
      log(warn);
      if (dom.memoryDumpStatus) {
        dom.memoryDumpStatus.textContent = `${dom.memoryDumpStatus.textContent} ${warn}`;
      }
    }
    return loaded;
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  return loadApple2MemoryDumpBytes(bytes, offsetRaw, { label: file.name });
}

async function loadLastSavedApple2Dump() {
  if (!state.sim || !isApple2UiEnabled()) {
    setMemoryDumpStatus('Load the Apple II runner first.');
    return false;
  }

  const saved = loadLastMemoryDumpFromStorage();
  const source = saved || state.memory.lastSavedDump;
  if (!source) {
    setMemoryDumpStatus('No saved dump found.');
    return false;
  }

  if (dom.memoryDumpOffset) {
    dom.memoryDumpOffset.value = `0x${hexWord(source.offset)}`;
  }

  let pcStatus = null;
  let resetAfterLoad = false;
  if (source.startPc != null) {
    pcStatus = await applyApple2SnapshotStartPc(source.startPc);
    resetAfterLoad = !!pcStatus.applied;
    if (pcStatus?.pc != null) {
      setMemoryResetVectorInput(pcStatus.pc);
    }
  }

  const suffix = source.savedAtIso ? ` @ ${source.savedAtIso}` : '';
  const pcSuffix = pcStatus?.pc != null ? ` (PC=$${hexWord(pcStatus.pc)})` : '';
  const loaded = await loadApple2MemoryDumpBytes(source.bytes, source.offset, {
    label: `${source.label}${suffix}${pcSuffix}`,
    resetAfterLoad
  });

  if (loaded && pcStatus && !pcStatus.applied) {
    const warn = `Saved dump requested PC=$${hexWord(pcStatus.pc)} but could not apply it (${pcStatus.reason}).`;
    log(warn);
    if (dom.memoryDumpStatus) {
      dom.memoryDumpStatus.textContent = `${dom.memoryDumpStatus.textContent} ${warn}`;
    }
  }
  return loaded;
}

function fitApple2RamWindow(bytes, offset) {
  if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
    return { data: new Uint8Array(0), trimmed: false };
  }
  const off = Math.max(0, Math.trunc(offset));
  if (off >= APPLE2_RAM_BYTES) {
    return { data: new Uint8Array(0), trimmed: true };
  }
  const maxLen = APPLE2_RAM_BYTES - off;
  if (bytes.length <= maxLen) {
    return { data: bytes, trimmed: false };
  }
  return { data: bytes.subarray(0, maxLen), trimmed: true };
}

function patchApple2ResetVector(romBytes, pc) {
  const rom = new Uint8Array(romBytes);
  if (rom.length > 0x2FFD) {
    rom[0x2FFC] = pc & 0xff;
    rom[0x2FFD] = (pc >>> 8) & 0xff;
  }
  return rom;
}

async function ensureApple2BaseRomBytes() {
  if (state.apple2.baseRomBytes instanceof Uint8Array && state.apple2.baseRomBytes.length > 0) {
    return state.apple2.baseRomBytes;
  }

  const preset = currentRunnerPreset();
  const romPath = preset?.romPath || './samples/appleiigo.rom';

  try {
    const romResp = await fetch(romPath);
    if (!romResp.ok) {
      return null;
    }
    const romBytes = new Uint8Array(await romResp.arrayBuffer());
    if (romBytes.length === 0) {
      return null;
    }
    state.apple2.baseRomBytes = new Uint8Array(romBytes);
    return state.apple2.baseRomBytes;
  } catch (_err) {
    return null;
  }
}

async function applyApple2SnapshotStartPc(startPc) {
  const pc = parsePcLiteral(startPc);
  if (pc == null) {
    return { applied: false, pc: null, reason: 'missing' };
  }
  if (!state.sim || !isApple2UiEnabled()) {
    return { applied: false, pc, reason: 'runner inactive' };
  }

  const baseRom = await ensureApple2BaseRomBytes();
  if (!(baseRom instanceof Uint8Array) || baseRom.length === 0) {
    return { applied: false, pc, reason: 'rom unavailable' };
  }

  const patchedRom = patchApple2ResetVector(baseRom, pc);
  const ok = state.sim.apple2_load_rom(patchedRom);
  return { applied: !!ok, pc, reason: ok ? 'ok' : 'rom load failed' };
}

async function resetApple2WithMemoryVectorOverride() {
  if (!state.sim || !isApple2UiEnabled()) {
    setMemoryDumpStatus('Load the Apple II runner first.');
    return false;
  }

  const pcBefore = getApple2ProgramCounter();
  const raw = String(dom.memoryResetVector?.value || '').trim();
  let requestedPc = null;
  let usedOverride = false;

  if (raw) {
    requestedPc = parsePcLiteral(raw);
    if (requestedPc == null) {
      const msg = `Invalid reset vector "${raw}". Use $B82A, 0xB82A, or decimal.`;
      setMemoryDumpStatus(msg);
      log(msg);
      return false;
    }

    const pcStatus = await applyApple2SnapshotStartPc(requestedPc);
    if (!pcStatus.applied) {
      const msg = `Could not apply reset vector $${hexWord(requestedPc)} (${pcStatus.reason}).`;
      setMemoryDumpStatus(msg);
      log(msg);
      return false;
    }
    usedOverride = true;
    setMemoryResetVectorInput(pcStatus.pc);
  }

  const resetInfo = performApple2ResetSequence({ releaseCycles: 0 });
  const pcAfter = Number.isFinite(resetInfo?.pcAfter) ? (resetInfo.pcAfter & 0xffff) : getApple2ProgramCounter();

  if (pcAfter != null) {
    state.memory.followPc = true;
    if (dom.memoryFollowPc) {
      dom.memoryFollowPc.checked = true;
    }
    if (dom.memoryStart) {
      dom.memoryStart.value = `0x${hexWord(pcAfter)}`;
    }
  }

  refreshApple2Screen();
  refreshApple2Debug();
  refreshMemoryView();
  refreshWatchTable();
  refreshStatus();

  const beforePart = pcBefore != null ? `$${hexWord(pcBefore)}` : 'n/a';
  const afterPart = pcAfter != null ? `$${hexWord(pcAfter)}` : 'n/a';
  const transitionPart = ` PC ${beforePart} -> ${afterPart}.`;
  const msg = usedOverride
    ? `Reset complete using vector $${hexWord(requestedPc)}.${transitionPart}`
    : `Reset complete using current ROM reset vector.${transitionPart}`;
  setMemoryDumpStatus(msg);
  if (dom.memoryStatus) {
    dom.memoryStatus.textContent = msg;
  }
  log(msg);
  return true;
}

function performApple2ResetSequence(options = {}) {
  if (!state.sim) {
    return { pcBefore: null, pcAfter: null, releaseCycles: 0, usedResetSignal: false };
  }
  state.running = false;
  state.apple2.keyQueue = [];
  const parsedReleaseCycles = Number.parseInt(options.releaseCycles, 10);
  const releaseCycles = Number.isFinite(parsedReleaseCycles)
    ? Math.max(0, parsedReleaseCycles)
    : 10;
  const pcBefore = getApple2ProgramCounter();
  let usedResetSignal = false;

  if (state.sim.has_signal('reset')) {
    usedResetSignal = true;
    state.sim.poke('reset', 1);
    state.sim.apple2_run_cpu_cycles(1, 0, false);
    state.sim.poke('reset', 0);
    if (releaseCycles > 0) {
      state.sim.apple2_run_cpu_cycles(releaseCycles, 0, false);
    }
  } else {
    state.sim.reset();
  }

  state.cycle = 0;
  state.uiCyclesPending = 0;
  if (state.sim.trace_enabled()) {
    state.sim.trace_capture();
  }
  const pcAfter = getApple2ProgramCounter();
  return { pcBefore, pcAfter, releaseCycles, usedResetSignal };
}

async function loadApple2MemoryDumpBytes(bytes, offset, options = {}) {
  if (!state.sim || !isApple2UiEnabled()) {
    setMemoryDumpStatus('Load the Apple II runner first.');
    return false;
  }

  const off = Math.max(0, parseHexOrDec(offset, 0));
  const source = bytes instanceof Uint8Array ? bytes : new Uint8Array(0);
  const { data, trimmed } = fitApple2RamWindow(source, off);

  if (data.length === 0) {
    setMemoryDumpStatus('No bytes loaded (offset out of RAM window).');
    return false;
  }

  const ok = state.sim.apple2_load_ram(data, off);
  if (!ok) {
    setMemoryDumpStatus('Dump load failed (runner memory API unavailable).');
    return false;
  }

  if (options.resetAfterLoad) {
    const parsedResetReleaseCycles = Number.parseInt(options.resetReleaseCycles, 10);
    const resetReleaseCycles = Number.isFinite(parsedResetReleaseCycles)
      ? Math.max(0, parsedResetReleaseCycles)
      : 0;
    performApple2ResetSequence({ releaseCycles: resetReleaseCycles });
  }

  refreshApple2Screen();
  refreshApple2Debug();
  refreshMemoryView();
  refreshWatchTable();
  refreshStatus();

  const label = options.label || 'memory dump';
  const suffix = trimmed ? ` (trimmed to ${data.length} bytes)` : '';
  const msg = `Loaded ${label} at $${off.toString(16).toUpperCase().padStart(4, '0')} (${data.length} bytes)${suffix}`;
  setMemoryDumpStatus(msg);
  log(msg);
  return true;
}

async function loadKaratekaDump() {
  if (!state.sim || !isApple2UiEnabled()) {
    setMemoryDumpStatus('Load the Apple II runner first.');
    return;
  }

  try {
    const [romResp, dumpResp, metaResp] = await Promise.all([
      fetch('./samples/appleiigo.rom'),
      fetch('./samples/karateka_mem.bin'),
      fetch('./samples/karateka_mem_meta.txt')
    ]);

    if (!romResp.ok || !dumpResp.ok) {
      throw new Error(`asset fetch failed (rom=${romResp.status}, dump=${dumpResp.status})`);
    }

    let startPc = KARATEKA_PC;
    if (metaResp.ok) {
      const meta = await metaResp.text();
      const m = meta.match(/PC at dump:\s*\$([0-9A-Fa-f]+)/);
      if (m) {
        const parsedPc = Number.parseInt(m[1], 16);
        if (Number.isFinite(parsedPc)) {
          startPc = parsedPc & 0xffff;
        }
      }
    }

    const romBytes = new Uint8Array(await romResp.arrayBuffer());
    state.apple2.baseRomBytes = new Uint8Array(romBytes);
    const patchedRom = patchApple2ResetVector(romBytes, startPc);
    const romLoaded = state.sim.apple2_load_rom(patchedRom);
    if (!romLoaded) {
      throw new Error('apple2_load_rom returned false');
    }
    setMemoryResetVectorInput(startPc);

    const dumpBytes = new Uint8Array(await dumpResp.arrayBuffer());
    await loadApple2MemoryDumpBytes(dumpBytes, 0, {
      resetAfterLoad: true,
      resetReleaseCycles: 0,
      label: `Karateka dump (PC=$${startPc.toString(16).toUpperCase().padStart(4, '0')})`
    });
  } catch (err) {
    const msg = `Karateka load failed: ${err.message || err}`;
    setMemoryDumpStatus(msg);
    log(msg);
  }
}

function selectedClock() {
  const val = dom.clockSignal.value;
  if (!val || val === '__none__') {
    return null;
  }
  return val;
}

function maskForWidth(width) {
  if (width >= 64) {
    return (1n << 64n) - 1n;
  }
  return (1n << BigInt(width)) - 1n;
}

function refreshStatus() {
  const backendDef = getBackendDef(state.backend);
  if (!state.sim) {
    dom.simStatus.textContent = 'Simulator not initialized';
    dom.traceStatus.textContent = 'Trace disabled';
    if (dom.backendStatus) {
      dom.backendStatus.textContent = `Backend: ${backendDef.id}`;
    }
    if (dom.runnerStatus) {
      dom.runnerStatus.textContent = 'Runner not initialized';
    }
    return;
  }

  const sigs = state.sim.signal_count();
  const regs = state.sim.reg_count();
  const clk = selectedClock();
  const mode = clk ? state.sim.clock_mode(clk) : null;
  const clockPart = clk ? ` | clock ${clk}${mode && mode !== 'unknown' ? ` (${mode})` : ''}` : '';
  dom.simStatus.textContent = `Cycle ${state.cycle} | ${sigs} signals | ${regs} regs${clockPart} ${state.running ? '| RUNNING' : '| PAUSED'}`;
  dom.traceStatus.textContent = `Trace ${state.sim.trace_enabled() ? 'enabled' : 'disabled'} | changes ${state.sim.trace_change_count()}`;
  if (dom.backendStatus) {
    const notes = [];
    if (!state.sim.features.hasSignalIndex) {
      notes.push('name-mode');
    }
    if (!state.sim.features.hasLiveTrace) {
      notes.push('vcd-snapshot');
    }
    dom.backendStatus.textContent = `Backend: ${backendDef.id}${notes.length > 0 ? ` (${notes.join(', ')})` : ''}`;
  }

  if (dom.runnerStatus) {
    const preset = currentRunnerPreset();
    const apple2Flag = state.sim.apple2_mode() ? ' | apple2 mode' : '';
    dom.runnerStatus.textContent = `${preset.label}${apple2Flag} | ${backendDef.label}`;
  }

  if (isApple2UiEnabled() && dom.apple2KeyStatus) {
    dom.apple2KeyStatus.textContent = `Keyboard queue: ${state.apple2.keyQueue.length}`;
  }

  updateIoToggleUi();
}

function drainTrace() {
  if (!state.sim) {
    return;
  }
  const chunk = state.sim.trace_take_live_vcd();
  if (chunk) {
    state.parser.ingest(chunk);
  }
}

function refreshWatchTable() {
  if (!state.sim) {
    dom.watchTableBody.innerHTML = '';
    state.watchRows = [];
    return;
  }

  const rows = [];
  for (const [name, info] of state.watches.entries()) {
    const value = info.idx != null ? state.sim.peek_by_idx(info.idx) : state.sim.peek(name);
    rows.push({ name, width: info.width, idx: info.idx, value });
  }

  state.watchRows = rows;
  dom.watchTableBody.innerHTML = rows
    .map((row) => `<tr><td>${row.name}</td><td>${row.width}</td><td>${formatValue(row.value, row.width)}</td></tr>`)
    .join('');
}

function renderWatchList() {
  const names = Array.from(state.watches.keys());
  dom.watchList.innerHTML = names
    .map((name) => `<li>${name}<button data-watch-remove="${name}" title="remove">x</button></li>`)
    .join('');
}

function renderBreakpointList() {
  dom.bpList.innerHTML = state.breakpoints
    .map((bp) => `<li>${bp.name}=${formatValue(bp.value, bp.width)}<button data-bp-remove="${bp.name}" title="remove">x</button></li>`)
    .join('');
}

function populateClockSelect() {
  const current = dom.clockSignal.value;
  dom.clockSignal.innerHTML = '<option value="__none__">(none)</option>';
  if (!state.irMeta) {
    return;
  }

  const clocks = state.irMeta.clockCandidates || state.irMeta.clocks || [];
  for (const clk of clocks) {
    const option = document.createElement('option');
    option.value = clk;
    if (state.sim) {
      const mode = state.sim.clock_mode(clk);
      option.textContent = `${clk} (${mode})`;
    } else {
      option.textContent = clk;
    }
    dom.clockSignal.appendChild(option);
  }

  if (current && clocks.includes(current)) {
    dom.clockSignal.value = current;
    return;
  }

  if (clocks.length > 0) {
    const preset = currentRunnerPreset();
    if (preset.id === 'apple2' && clocks.includes('clk_14m')) {
      dom.clockSignal.value = 'clk_14m';
      return;
    }
    const preferred = clocks.find((clk) => /^(clk|clock)$/i.test(clk));
    dom.clockSignal.value = preferred || clocks[0];
  }
}

function initializeTrace() {
  if (!state.sim) {
    return;
  }

  state.sim.trace_clear();
  state.sim.trace_clear_signals();
  state.sim.trace_all_signals();
  state.sim.trace_set_timescale('1ns');
  state.sim.trace_set_module_name('rhdl_top');
  state.sim.trace_start();
  state.sim.trace_capture();
  state.parser.reset();
  drainTrace();
}

function addWatchSignal(name) {
  if (!state.sim || !name) {
    return false;
  }

  if (state.watches.has(name)) {
    return false;
  }

  let idx = null;
  if (state.sim.features.hasSignalIndex) {
    const resolved = state.sim.get_signal_idx(name);
    if (resolved < 0) {
      log(`Unknown signal: ${name}`);
      return false;
    }
    idx = resolved;
  } else if (!state.sim.has_signal(name)) {
    log(`Unknown signal: ${name}`);
    return false;
  }

  const width = state.irMeta?.widths.get(name) || 1;
  state.watches.set(name, { idx, width });
  state.sim.trace_add_signal(name);
  refreshWatchTable();
  renderWatchList();
  return true;
}

function removeWatchSignal(name) {
  const had = state.watches.delete(name);
  if (!had) {
    return false;
  }
  refreshWatchTable();
  renderWatchList();
  return true;
}

function checkBreakpoints() {
  for (const bp of state.breakpoints) {
    const current = toBigInt(bp.idx != null ? state.sim.peek_by_idx(bp.idx) : state.sim.peek(bp.name));
    if (current === bp.value) {
      return { signal: bp.name, value: current };
    }
  }
  return null;
}

function apple2TextLineAddress(row) {
  const group = Math.floor(row / 8);
  const lineInGroup = row % 8;
  return 0x0400 + (lineInGroup * 0x80) + (group * 0x28);
}

function apple2DecodeChar(code) {
  const c = code & 0x7f;
  if (c >= 0x20 && c <= 0x7e) {
    return String.fromCharCode(c);
  }
  return ' ';
}

function refreshApple2Screen() {
  if (!dom.apple2TextScreen) {
    return;
  }
  if (!isApple2UiEnabled()) {
    dom.apple2TextScreen.textContent = 'Load the Apple II runner to use this tab.';
    if (dom.apple2HiresCanvas) {
      const ctx = dom.apple2HiresCanvas.getContext('2d');
      if (ctx) {
        ctx.clearRect(0, 0, dom.apple2HiresCanvas.width, dom.apple2HiresCanvas.height);
      }
    }
    updateIoToggleUi();
    return;
  }

  updateIoToggleUi();

  if (state.apple2.displayHires && dom.apple2HiresCanvas) {
    const mem = state.sim.apple2_read_ram(0x2000, 0x2000);
    if (!mem || mem.length === 0) {
      dom.apple2TextScreen.textContent = 'Apple II hi-res page unavailable';
      return;
    }

    const canvas = dom.apple2HiresCanvas;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
      return;
    }

    const image = ctx.createImageData(canvas.width, canvas.height);
    const out = image.data;

    for (let row = 0; row < 192; row += 1) {
      const lineBase = apple2HiresLineAddress(row) - 0x2000;
      for (let byteCol = 0; byteCol < 40; byteCol += 1) {
        const b = mem[lineBase + byteCol] || 0;
        const palette = (b >> 7) & 1;

        for (let bit = 0; bit < 7; bit += 1) {
          const pixelOn = (b >> bit) & 1;
          const x = byteCol * 7 + bit;
          const idx = (row * canvas.width + x) * 4;

          if (!pixelOn) {
            out[idx + 0] = 5;
            out[idx + 1] = 12;
            out[idx + 2] = 20;
            out[idx + 3] = 255;
            continue;
          }

          if (!state.apple2.displayColor) {
            out[idx + 0] = 140;
            out[idx + 1] = 255;
            out[idx + 2] = 170;
            out[idx + 3] = 255;
            continue;
          }

          const parity = (x + palette) & 1;
          if (palette === 0) {
            if (parity === 0) {
              out[idx + 0] = 120;
              out[idx + 1] = 255;
              out[idx + 2] = 120;
            } else {
              out[idx + 0] = 255;
              out[idx + 1] = 120;
              out[idx + 2] = 210;
            }
          } else if (parity === 0) {
            out[idx + 0] = 120;
            out[idx + 1] = 170;
            out[idx + 2] = 255;
          } else {
            out[idx + 0] = 255;
            out[idx + 1] = 195;
            out[idx + 2] = 120;
          }
          out[idx + 3] = 255;
        }
      }
    }

    ctx.putImageData(image, 0, 0);
    return;
  }

  const dump = state.sim.apple2_read_ram(0x0400, 0x0400);
  if (!dump || dump.length === 0) {
    dom.apple2TextScreen.textContent = 'Apple II text page unavailable';
    return;
  }

  const lines = [];
  for (let row = 0; row < 24; row += 1) {
    const base = apple2TextLineAddress(row) - 0x0400;
    let line = '';
    for (let col = 0; col < 40; col += 1) {
      line += apple2DecodeChar(dump[base + col] || 0);
    }
    lines.push(line);
  }
  dom.apple2TextScreen.textContent = lines.join('\n');
}

function refreshApple2Debug() {
  if (!dom.apple2DebugBody) {
    return;
  }
  if (!isApple2UiEnabled()) {
    dom.apple2DebugBody.innerHTML = '<tr><td colspan="2">Apple II runner inactive</td></tr>';
    if (dom.apple2SpeakerToggles) {
      dom.apple2SpeakerToggles.textContent = 'Speaker toggles: -';
    }
    return;
  }

  const get = (name) => (state.sim.has_signal(name) ? state.sim.peek(name) : 0);
  const rows = [
    ['pc_debug', `0x${(get('pc_debug') & 0xffff).toString(16).toUpperCase().padStart(4, '0')}`],
    ['opcode_debug', `0x${(get('opcode_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
    ['a_debug', `0x${(get('a_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
    ['x_debug', `0x${(get('x_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
    ['y_debug', `0x${(get('y_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
    ['s_debug', `0x${(get('s_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
    ['p_debug', `0x${(get('p_debug') & 0xff).toString(16).toUpperCase().padStart(2, '0')}`],
    ['q3', `${get('clk_2m') & 0x1}`],
    ['speaker', `${get('speaker') & 0x1}`]
  ];

  dom.apple2DebugBody.innerHTML = rows
    .map(([name, value]) => `<tr><td>${name}</td><td>${value}</td></tr>`)
    .join('');

  if (dom.apple2SpeakerToggles) {
    const toggles = state.apple2.lastCpuResult?.speaker_toggles || 0;
    dom.apple2SpeakerToggles.textContent = `Speaker toggles (last batch): ${toggles}`;
  }
}

function getApple2ProgramCounter() {
  if (!state.sim || !isApple2UiEnabled()) {
    return null;
  }

  const candidates = ['pc_debug', 'cpu__debug_pc', 'reg_pc'];
  for (const name of candidates) {
    if (state.sim.has_signal(name)) {
      return state.sim.peek(name) & 0xffff;
    }
  }
  return null;
}

function readApple2MappedMemory(start, length) {
  if (!state.sim || !isApple2UiEnabled()) {
    return new Uint8Array(0);
  }

  const len = Math.max(0, Number.parseInt(length, 10) || 0);
  if (len === 0) {
    return new Uint8Array(0);
  }

  const out = new Uint8Array(len);
  let addr = Number(start) & 0xffff;
  let cursor = 0;

  while (cursor < len) {
    const span = Math.min(len - cursor, APPLE2_ADDR_SPACE - addr);
    const chunk = state.sim.apple2_read_memory(addr, span);
    if (chunk && chunk.length > 0) {
      out.set(chunk.subarray(0, Math.min(span, chunk.length)), cursor);
    }
    cursor += span;
    addr = (addr + span) & 0xffff;
  }

  return out;
}

function format6502Operand(mode, addr, readByte) {
  const b1 = readByte((addr + 1) & 0xffff);
  const b2 = readByte((addr + 2) & 0xffff);
  const word = (b2 << 8) | b1;

  switch (mode) {
    case 'imp':
      return { bytes: 1, operand: '' };
    case 'acc':
      return { bytes: 1, operand: 'A' };
    case 'imm':
      return { bytes: 2, operand: `#$${hexByte(b1)}` };
    case 'zp':
      return { bytes: 2, operand: `$${hexByte(b1)}` };
    case 'zpx':
      return { bytes: 2, operand: `$${hexByte(b1)},X` };
    case 'zpy':
      return { bytes: 2, operand: `$${hexByte(b1)},Y` };
    case 'abs':
      return { bytes: 3, operand: `$${hexWord(word)}` };
    case 'absx':
      return { bytes: 3, operand: `$${hexWord(word)},X` };
    case 'absy':
      return { bytes: 3, operand: `$${hexWord(word)},Y` };
    case 'ind':
      return { bytes: 3, operand: `($${hexWord(word)})` };
    case 'indx':
      return { bytes: 2, operand: `($${hexByte(b1)},X)` };
    case 'indy':
      return { bytes: 2, operand: `($${hexByte(b1)}),Y` };
    case 'rel': {
      const offset = b1 > 0x7f ? b1 - 0x100 : b1;
      const target = (addr + 2 + offset) & 0xffff;
      return { bytes: 2, operand: `$${hexWord(target)}` };
    }
    default:
      return { bytes: 1, operand: '' };
  }
}

function disassemble6502Lines(startAddress, lineCount, highlightPc = null) {
  const count = Math.max(1, Math.min(128, Number.parseInt(lineCount, 10) || 1));
  const start = Number(startAddress) & 0xffff;
  const fetchLen = (count * 3) + 3;
  const memory = readApple2MappedMemory(start, fetchLen);

  const readByte = (addr) => {
    const normalized = addr & 0xffff;
    const offset = (normalized - start + APPLE2_ADDR_SPACE) & 0xffff;
    if (offset < memory.length) {
      return memory[offset];
    }
    return 0;
  };

  let addr = start;
  const lines = [];
  for (let i = 0; i < count; i += 1) {
    const opcode = readByte(addr);
    const info = MOS6502_MNEMONICS[opcode];
    let mnemonic = '???';
    let bytes = 1;
    let operand = '';

    if (info) {
      mnemonic = info[0];
      const decoded = format6502Operand(info[1], addr, readByte);
      bytes = decoded.bytes;
      operand = decoded.operand;
    }

    const encoded = [];
    for (let b = 0; b < bytes; b += 1) {
      encoded.push(hexByte(readByte((addr + b) & 0xffff)));
    }

    const marker = highlightPc != null && (highlightPc & 0xffff) === addr ? '>>' : '  ';
    const op = operand ? ` ${operand}` : '';
    lines.push(`${marker} ${hexWord(addr)}: ${encoded.join(' ').padEnd(8, ' ')}  ${mnemonic}${op}`);
    addr = (addr + bytes) & 0xffff;
  }

  return lines;
}

function refreshMemoryView() {
  if (!dom.memoryDump || !state.sim) {
    if (dom.memoryDump) {
      dom.memoryDump.textContent = '';
    }
    if (dom.memoryDisassembly) {
      dom.memoryDisassembly.textContent = '';
    }
    return;
  }

  if (dom.memoryFollowPc) {
    dom.memoryFollowPc.disabled = !isApple2UiEnabled();
    dom.memoryFollowPc.checked = !!state.memory.followPc;
  }

  if (!isApple2UiEnabled()) {
    dom.memoryDump.textContent = 'Load the Apple II runner to browse memory.';
    if (dom.memoryDisassembly) {
      dom.memoryDisassembly.textContent = 'Load the Apple II runner to view disassembly.';
    }
    setMemoryDumpStatus('Memory dump loading requires the Apple II runner.');
    return;
  }

  let start = Math.max(0, parseHexOrDec(dom.memoryStart?.value, 0)) & 0xffff;
  const length = Math.max(1, Math.min(1024, parseHexOrDec(dom.memoryLength?.value, 256)));
  const pc = getApple2ProgramCounter();

  if (state.memory.followPc && pc != null) {
    const maxStart = Math.max(0, APPLE2_ADDR_SPACE - length);
    const centered = Math.max(0, (pc & 0xffff) - Math.floor(length / 2));
    start = Math.min(maxStart, centered) & ~0x0f;
    if (dom.memoryStart) {
      dom.memoryStart.value = `0x${hexWord(start)}`;
    }
  }

  const data = readApple2MappedMemory(start, length);

  if (!data || data.length === 0) {
    dom.memoryDump.textContent = 'No memory data';
    if (dom.memoryDisassembly) {
      dom.memoryDisassembly.textContent = 'No disassembly data';
    }
    return;
  }

  const lines = [];
  for (let i = 0; i < data.length; i += 16) {
    const row = data.slice(i, i + 16);
    const hex = Array.from(row, (b) => hexByte(b)).join(' ');
    const ascii = Array.from(row, (b) => (b >= 32 && b <= 126 ? String.fromCharCode(b) : '.')).join('');
    const addr = (start + i) & 0xffff;
    const hasPc = pc != null && (((pc & 0xffff) - addr + APPLE2_ADDR_SPACE) & 0xffff) < row.length;
    const marker = hasPc ? '>>' : '  ';
    lines.push(`${marker} ${hexWord(addr)}: ${hex.padEnd(16 * 3 - 1, ' ')}  ${ascii}`);
  }
  dom.memoryDump.textContent = lines.join('\n');

  if (dom.memoryDisassembly) {
    const disasmStart = state.memory.followPc && pc != null ? (pc & 0xffff) : start;
    dom.memoryDisassembly.textContent = disassemble6502Lines(disasmStart, state.memory.disasmLines, pc).join('\n');
  }
}

function queueApple2Key(value) {
  if (!isApple2UiEnabled()) {
    return;
  }
  if (value == null) {
    return;
  }

  let ascii = typeof value === 'number' ? value : String(value).charCodeAt(0);
  if (!Number.isFinite(ascii)) {
    return;
  }

  if (ascii >= 97 && ascii <= 122) {
    ascii -= 32;
  }
  if (ascii === 10) {
    ascii = 0x0d;
  }
  if (ascii === 127) {
    ascii = 0x08;
  }

  state.apple2.keyQueue.push(ascii & 0xff);
  refreshStatus();
}

function runApple2Cycles(cycles) {
  if (!state.sim || !isApple2UiEnabled()) {
    return;
  }

  const key = state.apple2.keyQueue[0];
  const keyReady = state.apple2.keyQueue.length > 0;
  const result = state.sim.apple2_run_cpu_cycles(cycles, key || 0, keyReady);
  if (!result) {
    return;
  }

  if (result.key_cleared && state.apple2.keyQueue.length > 0) {
    state.apple2.keyQueue.shift();
  }

  state.apple2.lastCpuResult = result;
  state.apple2.lastSpeakerToggles = result.speaker_toggles;
  state.cycle += result.cycles_run;
  updateApple2SpeakerAudio(result.speaker_toggles, result.cycles_run);

  if (state.sim.trace_enabled()) {
    state.sim.trace_capture();
  }
}

function stepSimulation() {
  if (!state.sim) {
    return;
  }

  const ticks = Math.max(1, Number.parseInt(dom.stepTicks.value, 10) || 1);

  try {
    if (isApple2UiEnabled()) {
      runApple2Cycles(ticks);
    } else {
      const clk = selectedClock();
      if (clk) {
        state.sim.run_clock_ticks(clk, ticks);
      } else {
        state.sim.run_ticks(ticks);
      }
      state.cycle += ticks;
    }
  } catch (err) {
    log(`Step error: ${err.message || err}`);
    state.running = false;
  }

  drainTrace();
  refreshWatchTable();
  refreshApple2Screen();
  refreshApple2Debug();
  refreshMemoryView();
  if (isComponentTabActive()) {
    refreshActiveComponentTab();
  }
  state.uiCyclesPending = 0;
  refreshStatus();
}

function runFrame() {
  if (!state.running || !state.sim) {
    refreshStatus();
    return;
  }

  const batch = Math.max(1, Number.parseInt(dom.runBatch.value, 10) || 20000);
  const uiEvery = Math.max(1, Number.parseInt(dom.uiUpdateCycles?.value, 10) || batch);
  let hit = null;
  let cyclesRan = 0;

  try {
    if (isApple2UiEnabled()) {
      const before = state.cycle;
      runApple2Cycles(batch);
      cyclesRan = Math.max(0, state.cycle - before);
    } else {
      const clk = selectedClock();
      for (let i = 0; i < batch; i += 1) {
        if (clk) {
          state.sim.run_clock_ticks(clk, 1);
        } else {
          state.sim.run_ticks(1);
        }
        state.cycle += 1;
        cyclesRan += 1;

        hit = checkBreakpoints();
        if (hit) {
          break;
        }
      }
    }

    if (hit) {
      state.running = false;
      log(`Breakpoint hit at cycle ${state.cycle}: ${hit.signal}=${formatValue(hit.value, 64)}`);
    }
  } catch (err) {
    state.running = false;
    log(`Run error: ${err.message || err}`);
  }

  state.uiCyclesPending = Math.max(0, state.uiCyclesPending + cyclesRan);
  const shouldRefreshUi = !state.running
    || !!hit
    || state.uiCyclesPending >= uiEvery
    || state.activeTab === 'memoryTab'
    || isComponentTabActive();

  if (shouldRefreshUi) {
    drainTrace();
    refreshWatchTable();
    refreshApple2Screen();
    refreshApple2Debug();
    if (state.activeTab === 'memoryTab') {
      refreshMemoryView();
    }
    if (isComponentTabActive()) {
      refreshActiveComponentTab();
    }
    state.uiCyclesPending = 0;
  }

  refreshStatus();
  if (state.running) {
    requestAnimationFrame(runFrame);
  }
}

function setupP5() {
  const sketch = (p) => {
    const leftPad = 170;

    const resize = () => {
      const w = Math.max(300, dom.canvasWrap.clientWidth);
      const h = Math.max(220, dom.canvasWrap.clientHeight);
      p.resizeCanvas(w, h);
    };

    p.setup = () => {
      p.createCanvas(dom.canvasWrap.clientWidth, dom.canvasWrap.clientHeight).parent('canvasWrap');
      state.waveformP5 = p;
      p.textFont(waveformFontFamily());
      p.textSize(11);
    };

    p.windowResized = resize;

    p.draw = () => {
      const palette = waveformPalette();
      p.background(...palette.bg);
      p.stroke(...palette.axis);
      p.line(leftPad, 0, leftPad, p.height);

      if (!state.sim) {
        p.noStroke();
        p.fill(...palette.hint);
        p.text('Initialize simulator to view waveforms', 16, 24);
        return;
      }

      const rows = state.watchRows;
      if (!rows || rows.length === 0) {
        p.noStroke();
        p.fill(...palette.hint);
        p.text('Add watch signals to render traces', 16, 24);
        return;
      }

      const latest = Math.max(1, state.parser.latestTime());
      const visibleTicks = 1200;
      const startT = Math.max(0, latest - visibleTicks);
      const rowH = Math.max(28, Math.floor((p.height - 20) / rows.length));
      const plotW = p.width - leftPad - 8;

      const xFor = (t) => leftPad + ((t - startT) / Math.max(1, latest - startT)) * plotW;
      const yFor = (rowTop, rowHeight, value, width) => {
        if (width <= 1) {
          return value ? rowTop + 6 : rowTop + rowHeight - 6;
        }

        const bits = Math.min(width, 20);
        const max = Math.max(1, (2 ** bits) - 1);
        const clamped = Math.min(value, max);
        return rowTop + rowHeight - 6 - (clamped / max) * (rowHeight - 12);
      };

      rows.forEach((row, i) => {
        const top = 10 + i * rowH;
        const bottom = top + rowH;

        p.stroke(...palette.grid);
        p.line(0, bottom, p.width, bottom);

        p.noStroke();
        p.fill(...palette.label);
        p.text(`${row.name} [${row.width}]`, 8, top + 12);

        const series = state.parser.series(row.name);
        const fallback = state.parser.value(row.name);
        const initial = fallback == null ? Number(row.value) : fallback;

        let prevT = startT;
        let prevV = initial;

        for (const sample of series) {
          if (sample.t < startT) {
            prevT = startT;
            prevV = sample.v;
            continue;
          }

          const x0 = xFor(prevT);
          const x1 = xFor(sample.t);
          const y0 = yFor(top, rowH, prevV, row.width);
          const y1 = yFor(top, rowH, sample.v, row.width);

          p.stroke(...palette.trace);
          p.line(x0, y0, x1, y0);
          p.line(x1, y0, x1, y1);

          prevT = sample.t;
          prevV = sample.v;
        }

        const xTail = xFor(prevT);
        const xEnd = xFor(latest);
        const yTail = yFor(top, rowH, prevV, row.width);
        p.stroke(...palette.trace);
        p.line(xTail, yTail, xEnd, yTail);

        p.noStroke();
        p.fill(...palette.value);
        p.text(formatValue(row.value, row.width), p.width - 95, top + 12);
      });

      p.noStroke();
      p.fill(...palette.time);
      p.text(`t=${latest}`, p.width - 70, p.height - 8);
    };
  };

  new p5(sketch);
}

async function loadWasmInstance(backend = state.backend) {
  const def = getBackendDef(backend);
  const url = def.wasmPath;
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to fetch ${url}: ${response.status}`);
  }

  if (WebAssembly.instantiateStreaming) {
    try {
      const result = await WebAssembly.instantiateStreaming(response.clone(), {});
      return result.instance;
    } catch (_err) {
      // fallback below
    }
  }

  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, {});
  return result.instance;
}

async function ensureBackendInstance(backend = state.backend) {
  if (state.backendInstances.has(backend)) {
    state.instance = state.backendInstances.get(backend);
    return state.instance;
  }
  const instance = await loadWasmInstance(backend);
  state.backendInstances.set(backend, instance);
  state.instance = instance;
  return instance;
}

async function initializeSimulator(options = {}) {
  const json = String(options.simJson ?? dom.irJson?.value ?? '').trim();
  if (!json) {
    log('No IR JSON provided');
    return;
  }

  if (dom.irJson && json !== dom.irJson.value.trim()) {
    dom.irJson.value = json;
  }

  const preset = options.preset || getRunnerPreset(dom.runnerSelect?.value || state.runnerPreset);
  state.runnerPreset = preset.id;
  setComponentSourceBundle(options.componentSourceBundle || null);
  setComponentSchematicBundle(options.componentSchematicBundle || null);

  try {
    if (!state.instance) {
      await ensureBackendInstance(state.backend);
    }
    const meta = parseIrMeta(json);
    let explorerSource = String(options.explorerSource ?? json);
    let explorerMeta = options.explorerMeta || null;
    if (!explorerMeta && explorerSource && explorerSource !== json) {
      try {
        explorerMeta = parseIrMeta(explorerSource);
      } catch (err) {
        log(`Explorer IR parse failed, using simulation IR: ${err.message || err}`);
      }
    }
    if (!explorerMeta) {
      explorerMeta = meta;
      explorerSource = json;
    }

    if (explorerMeta !== meta) {
      explorerMeta = { ...explorerMeta, liveSignalNames: meta.names };
    }

    if (state.sim) {
      state.sim.destroy();
    }

    state.sim = new WasmIrSimulator(state.instance, json, state.backend);
    state.irMeta = meta;
    state.cycle = 0;
    state.uiCyclesPending = 0;
    state.running = false;
    state.watches.clear();
    state.breakpoints = [];
    state.apple2.enabled = false;
    state.apple2.keyQueue = [];
    state.apple2.lastCpuResult = null;
    state.apple2.lastSpeakerToggles = 0;
    state.apple2.baseRomBytes = null;
    updateApple2SpeakerAudio(0, 0);
    setMemoryDumpStatus('');
    setMemoryResetVectorInput(null);

    initializeTrace();
    populateClockSelect();

    const outputs = state.sim.output_names();
    for (const name of outputs.slice(0, 4)) {
      addWatchSignal(name);
    }

    const clk = selectedClock();
    if (clk) {
      addWatchSignal(clk);
    } else if (meta.clocks.length > 0) {
      addWatchSignal(meta.clocks[0]);
    }

    if (state.sim.apple2_mode()) {
      state.apple2.enabled = true;
      const defaultApple2Watches = ['pc_debug', 'a_debug', 'x_debug', 'y_debug', 'opcode_debug', 'speaker'];
      for (const name of defaultApple2Watches) {
        if (state.sim.has_signal(name)) {
          addWatchSignal(name);
        }
      }

      if (preset?.enableApple2Ui && preset.romPath) {
        try {
          const romResp = await fetch(preset.romPath);
          if (romResp.ok) {
            const romBytes = new Uint8Array(await romResp.arrayBuffer());
            state.apple2.baseRomBytes = new Uint8Array(romBytes);
            state.sim.apple2_load_rom(romBytes);
            log(`Loaded Apple II ROM: ${preset.romPath}`);
          } else {
            log(`Apple II ROM load skipped (${romResp.status})`);
          }
        } catch (err) {
          log(`Failed to load Apple II ROM: ${err.message || err}`);
        }
      }
    }

    renderWatchList();
    renderBreakpointList();
    refreshWatchTable();
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    if (explorerSource !== json) {
      setComponentSourceOverride(explorerSource, explorerMeta);
    } else {
      clearComponentSourceOverride();
    }
    rebuildComponentExplorer(explorerMeta, explorerSource);
    refreshStatus();
    log('Simulator initialized');
  } catch (err) {
    log(`Initialization failed: ${err.message || err}`);
  }
}

async function loadSample(samplePathOverride = null) {
  const samplePath = samplePathOverride || dom.sampleSelect?.value || './samples/toggle.json';
  const sampleLabel = dom.sampleSelect?.selectedOptions?.[0]?.textContent?.trim() || samplePath;
  try {
    const response = await fetch(samplePath);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    dom.irJson.value = await response.text();
    clearComponentSourceOverride();
    resetComponentExplorerState();
    log(`Loaded sample IR: ${sampleLabel}`);
    if (isComponentTabActive()) {
      refreshComponentExplorer();
    }
  } catch (err) {
    log(`Failed to load sample (${samplePath}): ${err.message || err}`);
  }
}

async function loadRunnerPreset() {
  const preset = getRunnerPreset(dom.runnerSelect?.value);
  state.runnerPreset = preset.id;
  updateIrSourceVisibility();
  try {
    let bundle = null;
    if (preset.usesManualIr) {
      if (!String(dom.irJson?.value || '').trim()) {
        await loadSample(preset.samplePath || null);
      }
      clearComponentSourceOverride();
      bundle = {
        simJson: String(dom.irJson?.value || '').trim(),
        explorerJson: String(dom.irJson?.value || '').trim(),
        explorerMeta: null,
        sourceBundle: null,
        schematicBundle: null
      };
    } else {
      bundle = await loadRunnerIrBundle(preset, { logLoad: true });
    }

    await initializeSimulator({
      preset,
      simJson: bundle.simJson,
      explorerSource: bundle.explorerJson,
      explorerMeta: bundle.explorerMeta,
      componentSourceBundle: bundle.sourceBundle || null,
      componentSchematicBundle: bundle.schematicBundle || null
    });
  } catch (err) {
    log(`Failed to load runner ${preset.label}: ${err.message || err}`);
    return;
  }
  setActiveTab(preset.preferredTab || 'vcdTab');
  refreshStatus();
}

async function start() {
  initializeCollapsiblePanels();
  initializeDashboardLayoutBuilder();
  try {
    state.backend = getBackendDef(dom.backendSelect?.value || state.backend).id;
    if (dom.backendSelect) {
      dom.backendSelect.value = state.backend;
    }
    let collapsed = false;
    let terminalOpen = false;
    let savedTheme = 'shenzhen';
    try {
      collapsed = localStorage.getItem(SIDEBAR_COLLAPSED_KEY) === '1';
      terminalOpen = localStorage.getItem(TERMINAL_OPEN_KEY) === '1';
      savedTheme = normalizeTheme(localStorage.getItem(THEME_KEY) || 'shenzhen');
    } catch (_err) {
      collapsed = false;
      terminalOpen = false;
      savedTheme = 'shenzhen';
    }
    setSidebarCollapsed(collapsed);
    setTerminalOpen(terminalOpen, { persist: false });
    applyTheme(savedTheme, { persist: false });
    await ensureBackendInstance(state.backend);
    dom.simStatus.textContent = `WASM ready (${state.backend})`;
    state.runnerPreset = dom.runnerSelect?.value || state.runnerPreset || 'apple2';
    if (dom.runnerSelect) {
      dom.runnerSelect.value = state.runnerPreset;
    }
    updateIrSourceVisibility();
    setActiveTab('vcdTab');
    updateIoToggleUi();
    renderComponentCodeViewButtons();
    setupP5();
    const startPreset = currentRunnerPreset();
    if (startPreset.usesManualIr) {
      clearComponentSourceBundle();
      clearComponentSchematicBundle();
      await loadSample(startPreset.samplePath || null);
    } else {
      const preloadBundle = await loadRunnerIrBundle(startPreset, { logLoad: false });
      setComponentSourceBundle(preloadBundle.sourceBundle || null);
      setComponentSchematicBundle(preloadBundle.schematicBundle || null);
    }
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    if (dom.terminalOutput && !dom.terminalOutput.textContent.trim()) {
      terminalWriteLine('Terminal ready. Type "help" for commands.');
    }
  } catch (err) {
    dom.simStatus.textContent = `WASM init failed: ${err.message || err}`;
    log(`WASM init failed: ${err.message || err}`);
    return;
  }

  dom.loadRunnerBtn?.addEventListener('click', loadRunnerPreset);
  dom.sidebarToggleBtn?.addEventListener('click', () => {
    setSidebarCollapsed(!state.sidebarCollapsed);
  });
  dom.terminalToggleBtn?.addEventListener('click', () => {
    setTerminalOpen(!state.terminalOpen, { focus: true });
  });
  dom.terminalRunBtn?.addEventListener('click', () => {
    submitTerminalInput();
  });
  dom.terminalInput?.addEventListener('keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await submitTerminalInput();
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      terminalHistoryNavigate(-1);
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      terminalHistoryNavigate(1);
    }
  });
  dom.themeSelect?.addEventListener('change', () => {
    applyTheme(dom.themeSelect.value);
  });
  dom.backendSelect?.addEventListener('change', async () => {
    const next = getBackendDef(dom.backendSelect.value).id;
    if (state.backend === next) {
      refreshStatus();
      return;
    }
    state.backend = next;
    try {
      await ensureBackendInstance(state.backend);
      dom.simStatus.textContent = `WASM ready (${state.backend})`;
      if (dom.irJson.value.trim()) {
        const preset = currentRunnerPreset();
        if (preset.usesManualIr) {
          await initializeSimulator({ preset });
        } else {
          const bundle = await loadRunnerIrBundle(preset, { logLoad: false });
          await initializeSimulator({
            preset,
            simJson: bundle.simJson,
            explorerSource: bundle.explorerJson,
            explorerMeta: bundle.explorerMeta,
            componentSourceBundle: bundle.sourceBundle || null,
            componentSchematicBundle: bundle.schematicBundle || null
          });
        }
      } else {
        refreshStatus();
      }
      log(`Switched backend to ${state.backend}`);
    } catch (err) {
      dom.simStatus.textContent = `Backend ${state.backend} unavailable: ${err.message || err}`;
      log(`Backend load failed (${state.backend}): ${err.message || err}`);
      if (dom.backendStatus) {
        dom.backendStatus.textContent = `Backend: ${state.backend} (unavailable)`;
      }
    }
  });
  dom.runnerSelect?.addEventListener('change', () => {
    state.runnerPreset = getRunnerPreset(dom.runnerSelect.value).id;
    updateIrSourceVisibility();
    refreshStatus();
  });

  dom.loadSampleBtn.addEventListener('click', () => {
    if (!currentRunnerPreset().usesManualIr) {
      return;
    }
    loadSample();
  });
  dom.sampleSelect?.addEventListener('change', () => {
    if (!currentRunnerPreset().usesManualIr) {
      return;
    }
    loadSample();
  });

  for (const btn of dom.tabButtons) {
    btn.addEventListener('click', () => {
      const tabId = btn.dataset.tab;
      if (tabId) {
        setActiveTab(tabId);
        if (tabId === 'memoryTab') {
          refreshMemoryView();
        } else if (tabId === 'componentTab' || tabId === 'componentGraphTab') {
          refreshComponentExplorer();
        }
      }
    });
  }

  dom.componentSearch?.addEventListener('input', () => {
    state.components.filter = String(dom.componentSearch.value || '').trim();
    renderComponentTree();
  });

  dom.componentSearchClearBtn?.addEventListener('click', () => {
    state.components.filter = '';
    if (dom.componentSearch) {
      dom.componentSearch.value = '';
    }
    renderComponentTree();
  });

  dom.componentCodeViewRhdl?.addEventListener('click', () => {
    setComponentCodeView('rhdl');
  });

  dom.componentCodeViewVerilog?.addEventListener('click', () => {
    setComponentCodeView('verilog');
  });

  dom.componentGraphTopBtn?.addEventListener('click', () => {
    const model = state.components.model;
    if (!model?.rootId) {
      return;
    }
    setComponentGraphFocus(model.rootId, true);
  });

  dom.componentGraphUpBtn?.addEventListener('click', () => {
    const focusNode = currentComponentGraphFocusNode();
    if (!focusNode?.parentId) {
      return;
    }
    setComponentGraphFocus(focusNode.parentId, true);
  });

  dom.componentTree?.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-component-id]');
    if (!button) {
      return;
    }
    const nodeId = button.dataset.componentId;
    if (!nodeId) {
      return;
    }
    if (state.components.selectedNodeId !== nodeId) {
      state.components.selectedNodeId = nodeId;
      renderComponentTree();
      renderComponentViews();
    }
  });

  dom.toggleHires?.addEventListener('change', () => {
    state.apple2.displayHires = !!dom.toggleHires.checked;
    if (!state.apple2.displayHires) {
      state.apple2.displayColor = false;
    }
    updateIoToggleUi();
    refreshApple2Screen();
  });

  dom.toggleColor?.addEventListener('change', () => {
    state.apple2.displayColor = !!dom.toggleColor.checked;
    if (state.apple2.displayColor) {
      state.apple2.displayHires = true;
    }
    updateIoToggleUi();
    refreshApple2Screen();
  });

  dom.toggleSound?.addEventListener('change', async () => {
    await setApple2SoundEnabled(!!dom.toggleSound.checked);
    if (!state.apple2.soundEnabled) {
      updateApple2SpeakerAudio(0, 0);
    }
    refreshStatus();
  });

  dom.irFileInput.addEventListener('change', async (event) => {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }
    dom.irJson.value = await file.text();
    clearComponentSourceOverride();
    resetComponentExplorerState();
    log(`Loaded IR file: ${file.name}`);
    if (isComponentTabActive()) {
      refreshComponentExplorer();
    }
  });

  dom.irJson?.addEventListener('input', () => {
    clearComponentSourceOverride();
    resetComponentExplorerState();
    if (isComponentTabActive()) {
      refreshComponentExplorer();
    }
  });

  dom.initBtn.addEventListener('click', initializeSimulator);

  dom.resetBtn.addEventListener('click', () => {
    if (!state.sim) {
      return;
    }
    if (isApple2UiEnabled()) {
      performApple2ResetSequence();
    } else {
      state.running = false;
      state.cycle = 0;
      state.uiCyclesPending = 0;
      state.sim.reset();
    }
    initializeTrace();
    refreshWatchTable();
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    if (isComponentTabActive()) {
      refreshActiveComponentTab();
    }
    updateApple2SpeakerAudio(0, 0);
    refreshStatus();
    log('Simulator reset');
  });

  dom.stepBtn.addEventListener('click', stepSimulation);

  dom.runBtn.addEventListener('click', () => {
    if (!state.sim || state.running) {
      return;
    }
    state.running = true;
    refreshStatus();
    requestAnimationFrame(runFrame);
  });

  dom.pauseBtn.addEventListener('click', () => {
    state.running = false;
    updateApple2SpeakerAudio(0, 0);
    drainTrace();
    refreshWatchTable();
    refreshApple2Screen();
    refreshApple2Debug();
    if (state.activeTab === 'memoryTab') {
      refreshMemoryView();
    } else if (isComponentTabActive()) {
      refreshActiveComponentTab();
    }
    state.uiCyclesPending = 0;
    refreshStatus();
    log('Simulation paused');
  });

  dom.traceStartBtn.addEventListener('click', () => {
    if (!state.sim) {
      return;
    }
    state.sim.trace_start();
    state.sim.trace_capture();
    drainTrace();
    refreshStatus();
  });

  dom.traceStopBtn.addEventListener('click', () => {
    if (!state.sim) {
      return;
    }
    state.sim.trace_stop();
    refreshStatus();
  });

  dom.traceClearBtn.addEventListener('click', () => {
    if (!state.sim) {
      return;
    }
    state.sim.trace_clear();
    state.parser.reset();
    refreshStatus();
    log('Trace cleared');
  });

  dom.downloadVcdBtn.addEventListener('click', () => {
    if (!state.sim) {
      return;
    }
    const vcd = state.sim.trace_to_vcd();
    const blob = new Blob([vcd], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'rhdl_trace.vcd';
    a.click();
    URL.revokeObjectURL(url);
    log('Saved VCD file');
  });

  dom.addWatchBtn.addEventListener('click', () => {
    const signal = dom.watchSignal.value.trim();
    if (!signal) {
      return;
    }
    addWatchSignal(signal);
    dom.watchSignal.value = '';
  });

  dom.watchList.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-watch-remove]');
    if (!button) {
      return;
    }
    removeWatchSignal(button.dataset.watchRemove);
  });

  dom.addBpBtn.addEventListener('click', () => {
    if (!state.sim) {
      return;
    }

    const signal = dom.bpSignal.value.trim();
    const valueRaw = dom.bpValue.value.trim();
    if (!signal || !valueRaw) {
      return;
    }

    const parsed = parseNumeric(valueRaw);
    if (parsed == null) {
      log('Invalid breakpoint value');
      return;
    }

    let idx = null;
    if (state.sim.features.hasSignalIndex) {
      const resolved = state.sim.get_signal_idx(signal);
      if (resolved < 0) {
        log(`Unknown signal for breakpoint: ${signal}`);
        return;
      }
      idx = resolved;
    } else if (!state.sim.has_signal(signal)) {
      log(`Unknown signal for breakpoint: ${signal}`);
      return;
    }

    const width = state.irMeta?.widths.get(signal) || 1;
    const mask = maskForWidth(width);
    const value = parsed & mask;

    state.breakpoints = state.breakpoints.filter((bp) => bp.name !== signal);
    state.breakpoints.push({ name: signal, idx, width, value });
    renderBreakpointList();
    log(`Breakpoint added: ${signal}=${valueRaw}`);

    dom.bpSignal.value = '';
    dom.bpValue.value = '';
  });

  dom.clearBpBtn.addEventListener('click', () => {
    state.breakpoints = [];
    renderBreakpointList();
    log('Breakpoints cleared');
  });

  dom.bpList.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-bp-remove]');
    if (!button) {
      return;
    }
    const name = button.dataset.bpRemove;
    state.breakpoints = state.breakpoints.filter((bp) => bp.name !== name);
    renderBreakpointList();
  });

  dom.clockSignal.addEventListener('change', () => {
    refreshStatus();
  });

  dom.apple2SendKeyBtn?.addEventListener('click', () => {
    const raw = dom.apple2KeyInput?.value || '';
    if (!raw) {
      return;
    }
    queueApple2Key(raw[0]);
    dom.apple2KeyInput.value = '';
  });

  dom.apple2KeyInput?.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      const raw = dom.apple2KeyInput?.value || '';
      queueApple2Key(raw ? raw[0] : '\r');
      dom.apple2KeyInput.value = '';
    }
  });

  dom.apple2ClearKeysBtn?.addEventListener('click', () => {
    state.apple2.keyQueue = [];
    refreshStatus();
  });

  dom.apple2TextScreen?.addEventListener('keydown', (event) => {
    if (!isApple2UiEnabled()) {
      return;
    }
    if (event.key.length === 1) {
      queueApple2Key(event.key);
      event.preventDefault();
      return;
    }
    if (event.key === 'Enter') {
      queueApple2Key('\r');
      event.preventDefault();
    } else if (event.key === 'Backspace') {
      queueApple2Key(String.fromCharCode(0x08));
      event.preventDefault();
    }
  });

  dom.memoryFollowPc?.addEventListener('change', () => {
    state.memory.followPc = !!dom.memoryFollowPc.checked;
    refreshMemoryView();
  });

  dom.memoryRefreshBtn?.addEventListener('click', refreshMemoryView);
  dom.memoryDumpLoadBtn?.addEventListener('click', async () => {
    if (!state.sim || !isApple2UiEnabled()) {
      setMemoryDumpStatus('Load the Apple II runner first.');
      return;
    }
    const file = dom.memoryDumpFile?.files?.[0];
    if (!file) {
      setMemoryDumpStatus('Select a dump/snapshot file first.');
      return;
    }

    const offsetRaw = dom.memoryDumpOffset?.value || '0';
    await loadApple2DumpOrSnapshotFile(file, offsetRaw);
  });

  dom.memoryDumpSaveBtn?.addEventListener('click', async () => {
    await saveApple2MemoryDump();
  });

  dom.memorySnapshotSaveBtn?.addEventListener('click', async () => {
    await saveApple2MemorySnapshot();
  });

  dom.memoryDumpLoadLastBtn?.addEventListener('click', async () => {
    await loadLastSavedApple2Dump();
  });

  dom.loadKaratekaBtn?.addEventListener('click', async () => {
    await loadKaratekaDump();
  });

  dom.memoryResetBtn?.addEventListener('click', async () => {
    setMemoryDumpStatus('Reset (Vector) requested...');
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = 'Reset (Vector) requested...';
    }
    await resetApple2WithMemoryVectorOverride();
  });

  dom.memoryResetVector?.addEventListener('keydown', async (event) => {
    if (event.key !== 'Enter') {
      return;
    }
    event.preventDefault();
    setMemoryDumpStatus('Reset (Vector) requested...');
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = 'Reset (Vector) requested...';
    }
    await resetApple2WithMemoryVectorOverride();
  });

  dom.memoryDumpFile?.addEventListener('change', () => {
    const file = dom.memoryDumpFile?.files?.[0];
    if (!file) {
      setMemoryDumpStatus('');
      return;
    }
    const label = isSnapshotFileName(file.name) ? 'snapshot' : 'dump';
    setMemoryDumpStatus(`Selected ${label}: ${file.name} (${file.size} bytes)`);
  });

  dom.memoryWriteBtn?.addEventListener('click', () => {
    if (!state.sim || !isApple2UiEnabled()) {
      return;
    }
    const addr = parseHexOrDec(dom.memoryWriteAddr?.value, -1);
    const value = parseHexOrDec(dom.memoryWriteValue?.value, -1);
    if (addr < 0 || value < 0) {
      if (dom.memoryStatus) {
        dom.memoryStatus.textContent = 'Invalid address or value';
      }
      return;
    }

    const ok = state.sim.apple2_write_ram(addr, new Uint8Array([value & 0xff]));
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = ok
        ? `Wrote $${hexByte(value & 0xff)} @ $${addr.toString(16).toUpperCase().padStart(4, '0')}`
        : 'Memory write failed';
    }
    refreshMemoryView();
    refreshApple2Screen();
  });
}

start();
