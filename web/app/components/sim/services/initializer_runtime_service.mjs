import { resolveRunnerIoConfig } from '../../runner/lib/io_config.mjs';
import { isSnapshotFileName, parseApple2SnapshotText } from '../../apple2/lib/snapshot.mjs';

const DEFAULT_APPLE2_WATCHES = ['pc_debug', 'a_debug', 'x_debug', 'y_debug', 'opcode_debug', 'speaker'];
const U16_MASK = 0xFFFF;
const RISCV_PHYSTOP_IMM20_ORIGINAL = 0x88000;
const RISCV_PHYSTOP_IMM20_MODERATE = 0x84000;
const RISCV_PHYSTOP_IMM20_AGGRESSIVE = 0x80200;

function didCallSucceed(result) {
  return result !== false;
}

function parseNonNegativeInt(value, fallback = 0) {
  const parsed = Number.parseInt(String(value ?? ''), 0);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return parsed >>> 0;
}

function parseOptionalPc(value) {
  if (value == null || value === '') {
    return null;
  }
  const parsed = Number.parseInt(String(value), 0);
  if (!Number.isFinite(parsed)) {
    return null;
  }
  return parsed >>> 0;
}

function normalizeDefaultBinSpace(value) {
  const token = String(value || 'main').trim().toLowerCase();
  if (token === 'boot' || token === 'bootrom' || token === 'boot_rom') {
    return 'boot_rom';
  }
  if (token === 'rom') {
    return 'rom';
  }
  return 'main';
}

function normalizeRiscvFastBootMode(value) {
  if (value === false || value == null) {
    return null;
  }
  if (value === true) {
    return 'moderate';
  }

  const token = String(value).trim().toLowerCase();
  if (token === 'moderate' || token === 'safe') {
    return 'moderate';
  }
  if (token === 'aggressive') {
    return 'aggressive';
  }
  return null;
}

function riscvFastBootPhystopImm20(mode) {
  if (mode === 'aggressive') {
    return RISCV_PHYSTOP_IMM20_AGGRESSIVE;
  }
  if (mode === 'moderate') {
    return RISCV_PHYSTOP_IMM20_MODERATE;
  }
  return null;
}

function resolveDefaultBinConfig(preset = {}) {
  const raw = preset?.defaultBin;
  if (!raw || typeof raw !== 'object') {
    return null;
  }

  const path = String(raw.path || '').trim();
  if (!path) {
    return null;
  }

  return {
    path,
    offset: parseNonNegativeInt(raw.offset, 0),
    space: normalizeDefaultBinSpace(raw.space),
    startPc: parseOptionalPc(raw.startPc),
    resetAfterLoad: raw.resetAfterLoad !== false,
    fastBootMode: normalizeRiscvFastBootMode(raw.fastBoot)
  };
}

function resolveDefaultDiskConfig(preset = {}) {
  const raw = preset?.defaultDisk;
  if (!raw || typeof raw !== 'object') {
    return null;
  }

  const path = String(raw.path || '').trim();
  if (!path) {
    return null;
  }

  return {
    path,
    offset: parseNonNegativeInt(raw.offset, 0),
    resetAfterLoad: raw.resetAfterLoad === true
  };
}

function applyRiscvFastBootPhystopPatch(bytes, targetImm20) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 4) {
    return 0;
  }
  const imm20Target = Number(targetImm20) >>> 0;
  if (imm20Target === 0) {
    return 0;
  }
  let patches = 0;
  for (let offset = 0; offset + 4 <= bytes.length; offset += 4) {
    const word = (
      (bytes[offset] & 0xFF)
      | ((bytes[offset + 1] & 0xFF) << 8)
      | ((bytes[offset + 2] & 0xFF) << 16)
      | ((bytes[offset + 3] & 0xFF) << 24)
    ) >>> 0;
    const opcode = word & 0x7F;
    if (opcode !== 0x37) {
      continue; // LUI only
    }
    const imm20 = (word >>> 12) & 0xFFFFF;
    if (imm20 !== RISCV_PHYSTOP_IMM20_ORIGINAL) {
      continue; // original PHYSTOP upper immediate (0x8800_0000)
    }
    const rd = (word >>> 7) & 0x1F;
    const patchedWord = (((imm20Target << 12) >>> 0) | (rd << 7) | 0x37) >>> 0;
    bytes[offset] = patchedWord & 0xFF;
    bytes[offset + 1] = (patchedWord >>> 8) & 0xFF;
    bytes[offset + 2] = (patchedWord >>> 16) & 0xFF;
    bytes[offset + 3] = (patchedWord >>> 24) & 0xFF;
    patches += 1;
  }
  return patches;
}

async function loadRunnerRomAsset({
  runtime,
  state,
  ioConfig,
  supportsRunnerApi,
  supportsGenericMemoryApi,
  fetchImpl,
  log
} = {}) {
  if (!ioConfig?.rom?.path) {
    return false;
  }

  try {
    const romResp = await fetchImpl(ioConfig.rom.path);
    if (!romResp.ok) {
      log(`Runner ROM load skipped (${romResp.status})`);
      return false;
    }

    const romBytes = new Uint8Array(await romResp.arrayBuffer());
    state.apple2.baseRomBytes = new Uint8Array(romBytes);

    if (supportsRunnerApi && typeof runtime.sim.runner_load_rom === 'function') {
      const ok = didCallSucceed(runtime.sim.runner_load_rom(romBytes, ioConfig.rom.offset || 0));
      if (ok) {
        log(`Loaded runner ROM via runner_load_rom: ${ioConfig.rom.path}`);
      } else {
        log(`Runner ROM load failed via runner API: ${ioConfig.rom.path}`);
      }
      return ok;
    }

    if (supportsGenericMemoryApi && typeof runtime.sim.memory_load === 'function') {
      const ok = didCallSucceed(runtime.sim.memory_load(romBytes, ioConfig.rom.offset || 0, { isRom: !!ioConfig.rom.isRom }));
      if (ok) {
        log(`Loaded runner ROM: ${ioConfig.rom.path}`);
      } else {
        log(`Runner ROM load failed: ${ioConfig.rom.path}`);
      }
      return ok;
    }
  } catch (err) {
    log(`Failed to load runner ROM: ${err.message || err}`);
  }

  return false;
}

async function loadDefaultBinAsset({
  runtime,
  defaultBin,
  supportsRunnerApi,
  supportsGenericMemoryApi,
  fetchImpl,
  log
} = {}) {
  if (!defaultBin?.path) {
    return false;
  }

  try {
    const binResp = await fetchImpl(defaultBin.path);
    if (!binResp.ok) {
      log(`Default bin load skipped (${binResp.status}): ${defaultBin.path}`);
      return false;
    }

    let bytes = null;
    let loadOffset = defaultBin.offset;
    let startPc = defaultBin.startPc;

    if (isSnapshotFileName(defaultBin.path)) {
      const snapshot = parseApple2SnapshotText(await binResp.text());
      if (!snapshot) {
        log(`Default snapshot parse failed: ${defaultBin.path}`);
        return false;
      }
      bytes = snapshot.bytes;
      if (Number.isFinite(snapshot.offset)) {
        loadOffset = Math.max(0, Number(snapshot.offset) || 0);
      }
      if (snapshot.startPc != null) {
        const parsedStart = Number(snapshot.startPc) >>> 0;
        const runnerKind = typeof runtime?.sim?.runner_kind === 'function'
          ? runtime.sim.runner_kind()
          : null;
        startPc = (runnerKind === 'mos6502' || runnerKind === 'apple2')
          ? (parsedStart & U16_MASK)
          : parsedStart;
      }
    } else {
      bytes = new Uint8Array(await binResp.arrayBuffer());
    }

    if (defaultBin.fastBootMode && defaultBin.space === 'main') {
      const runnerKind = typeof runtime?.sim?.runner_kind === 'function'
        ? runtime.sim.runner_kind()
        : null;
      if (runnerKind === 'riscv') {
        const phystopImm20 = riscvFastBootPhystopImm20(defaultBin.fastBootMode);
        const patches = applyRiscvFastBootPhystopPatch(bytes, phystopImm20);
        if (patches > 0) {
          const phystop = ((phystopImm20 << 12) >>> 0).toString(16).toUpperCase();
          log(`Applied RISC-V ${defaultBin.fastBootMode} fast-boot PHYSTOP patch (${patches} instruction${patches === 1 ? '' : 's'}, PHYSTOP=0x${phystop})`);
        }
      }
    }

    let loaded = false;

    if (defaultBin.space === 'boot_rom') {
      if (supportsRunnerApi && typeof runtime.sim.runner_load_boot_rom === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_boot_rom(bytes));
      }
    } else if (defaultBin.space === 'rom') {
      if (supportsRunnerApi && typeof runtime.sim.runner_load_rom === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_rom(bytes, loadOffset));
      } else if (supportsRunnerApi && typeof runtime.sim.runner_load_memory === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_memory(bytes, loadOffset, { isRom: true }));
      } else if (supportsGenericMemoryApi && typeof runtime.sim.memory_load === 'function') {
        loaded = didCallSucceed(runtime.sim.memory_load(bytes, loadOffset, { isRom: true }));
      }
    } else {
      if (supportsRunnerApi && typeof runtime.sim.runner_load_memory === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_memory(bytes, loadOffset, { isRom: false }));
      } else if (supportsGenericMemoryApi && typeof runtime.sim.memory_load === 'function') {
        loaded = didCallSucceed(runtime.sim.memory_load(bytes, loadOffset, { isRom: false }));
      }
    }

    if (!loaded) {
      log(`Default bin load failed or unsupported for space "${defaultBin.space}": ${defaultBin.path}`);
      return false;
    }

    let pcApplied = startPc == null;
    if (startPc != null && typeof runtime.sim.runner_set_reset_vector === 'function') {
      pcApplied = didCallSucceed(runtime.sim.runner_set_reset_vector(startPc));
      if (!pcApplied) {
        const width = startPc > 0xFFFF ? 8 : 4;
        log(`Default bin reset vector apply failed (PC=$${startPc.toString(16).padStart(width, '0')})`);
      }
    } else if (startPc != null) {
      pcApplied = false;
    }

    if (defaultBin.resetAfterLoad && typeof runtime.sim.reset === 'function') {
      runtime.sim.reset();
      await bootstrapMos6502Runner(runtime, log);
    }
    if (startPc != null) {
      const shouldApplyFallback = !pcApplied || riscvStartPcNeedsRepair(runtime, startPc);
      if (shouldApplyFallback) {
        applyRiscvStartPcFallback(runtime, startPc, log);
      }
    }

    log(`Loaded default bin (${defaultBin.space}) @ 0x${loadOffset.toString(16)}: ${defaultBin.path}`);
    return true;
  } catch (err) {
    log(`Failed to load default bin: ${err.message || err}`);
    return false;
  }
}

async function loadDefaultDiskAsset({
  runtime,
  defaultDisk,
  supportsRunnerApi,
  fetchImpl,
  log
} = {}) {
  if (!defaultDisk?.path) {
    return false;
  }

  try {
    const diskResp = await fetchImpl(defaultDisk.path);
    if (!diskResp.ok) {
      log(`Default disk load skipped (${diskResp.status}): ${defaultDisk.path}`);
      return false;
    }

    const bytes = new Uint8Array(await diskResp.arrayBuffer());
    let loaded = false;
    if (supportsRunnerApi && typeof runtime.sim.runner_riscv_load_disk === 'function') {
      loaded = didCallSucceed(runtime.sim.runner_riscv_load_disk(bytes, defaultDisk.offset));
    }
    if (!loaded) {
      log(`Default disk load failed or unsupported: ${defaultDisk.path}`);
      return false;
    }

    if (defaultDisk.resetAfterLoad && typeof runtime.sim.reset === 'function') {
      runtime.sim.reset();
    }

    log(`Loaded default disk @ 0x${defaultDisk.offset.toString(16)}: ${defaultDisk.path}`);
    return true;
  } catch (err) {
    log(`Failed to load default disk: ${err.message || err}`);
    return false;
  }
}

function readMos6502ResetVector(runtime) {
  if (!runtime?.sim || typeof runtime.sim.runner_read_memory !== 'function') {
    return null;
  }
  const loBytes = runtime.sim.runner_read_memory(0xFFFC, 1);
  const hiBytes = runtime.sim.runner_read_memory(0xFFFD, 1);
  const lo = loBytes instanceof Uint8Array && loBytes.length > 0 ? (loBytes[0] & 0xFF) : 0;
  const hi = hiBytes instanceof Uint8Array && hiBytes.length > 0 ? (hiBytes[0] & 0xFF) : 0;
  return ((hi << 8) | lo) & U16_MASK;
}

function readMos6502Byte(runtime, addr) {
  if (!runtime?.sim || typeof runtime.sim.runner_read_memory !== 'function') {
    return 0;
  }
  const bytes = runtime.sim.runner_read_memory(addr & U16_MASK, 1);
  return bytes instanceof Uint8Array && bytes.length > 0 ? (bytes[0] & 0xFF) : 0;
}

function pokeSignalIfPresent(runtime, name, value) {
  if (!runtime?.sim || typeof runtime.sim.has_signal !== 'function' || typeof runtime.sim.poke !== 'function') {
    return;
  }
  if (runtime.sim.has_signal(name)) {
    runtime.sim.poke(name, value);
  }
}

function applyRiscvStartPcFallback(runtime, startPc, log = () => {}) {
  if (!runtime?.sim) {
    return false;
  }
  const kind = typeof runtime.sim.runner_kind === 'function'
    ? runtime.sim.runner_kind()
    : null;
  if (kind !== 'riscv') {
    return false;
  }
  if (typeof runtime.sim.has_signal !== 'function' || typeof runtime.sim.poke !== 'function') {
    return false;
  }

  const vector = Number(startPc) >>> 0;
  let wroteAny = false;
  for (const signalName of ['pc_reg__pc', 'pc', 'debug_pc']) {
    if (runtime.sim.has_signal(signalName)) {
      runtime.sim.poke(signalName, vector);
      wroteAny = true;
    }
  }
  if (!wroteAny) {
    return false;
  }
  if (typeof runtime.sim.evaluate === 'function') {
    runtime.sim.evaluate();
  }

  log(`Applied RISC-V start PC fallback (PC=$${vector.toString(16).toUpperCase().padStart(8, '0')})`);
  return true;
}

function readRiscvProgramCounter(runtime) {
  if (!runtime?.sim || typeof runtime.sim.has_signal !== 'function' || typeof runtime.sim.peek !== 'function') {
    return null;
  }
  for (const name of ['debug_pc', 'pc_reg__pc', 'pc']) {
    if (!runtime.sim.has_signal(name)) {
      continue;
    }
    const value = Number(runtime.sim.peek(name));
    if (!Number.isFinite(value)) {
      continue;
    }
    return value >>> 0;
  }
  return null;
}

function riscvStartPcNeedsRepair(runtime, startPc) {
  if (!runtime?.sim || typeof runtime.sim.runner_kind !== 'function') {
    return false;
  }
  if (runtime.sim.runner_kind() !== 'riscv') {
    return false;
  }
  const expected = Number(startPc) >>> 0;
  const observed = readRiscvProgramCounter(runtime);
  if (observed == null) {
    return true;
  }
  if (observed === expected) {
    return false;
  }
  if (expected >= 0x80000000 && observed < 0x01000000) {
    return true;
  }
  return (expected >>> 24) !== (observed >>> 24);
}

function runBootstrapCycles(runtime, count) {
  const cycles = Math.max(0, Number.parseInt(count, 10) || 0);
  if (cycles <= 0 || !runtime?.sim) {
    return;
  }
  if (typeof runtime.sim.runner_run_cycles === 'function') {
    runtime.sim.runner_run_cycles(cycles, 0, false);
    return;
  }
  if (typeof runtime.sim.run_clock_ticks === 'function' && typeof runtime.sim.has_signal === 'function' && runtime.sim.has_signal('clk')) {
    runtime.sim.run_clock_ticks('clk', cycles);
    return;
  }
  if (typeof runtime.sim.run_ticks === 'function') {
    runtime.sim.run_ticks(cycles);
  }
}

async function bootstrapMos6502Runner(runtime, log = () => {}) {
  if (!runtime?.sim || typeof runtime.sim.runner_kind !== 'function') {
    return;
  }
  if (runtime.sim.runner_kind() !== 'mos6502') {
    return;
  }

  // Match examples/mos6502 IR runner reset/bootstrap flow so CPU starts at reset vector target.
  pokeSignalIfPresent(runtime, 'rst', 1);
  pokeSignalIfPresent(runtime, 'rdy', 1);
  pokeSignalIfPresent(runtime, 'irq', 1);
  pokeSignalIfPresent(runtime, 'nmi', 1);
  pokeSignalIfPresent(runtime, 'data_in', 0);
  pokeSignalIfPresent(runtime, 'ext_pc_load_en', 0);
  pokeSignalIfPresent(runtime, 'ext_a_load_en', 0);
  pokeSignalIfPresent(runtime, 'ext_x_load_en', 0);
  pokeSignalIfPresent(runtime, 'ext_y_load_en', 0);
  pokeSignalIfPresent(runtime, 'ext_sp_load_en', 0);

  runBootstrapCycles(runtime, 1); // one reset pulse cycle
  pokeSignalIfPresent(runtime, 'rst', 0);
  runBootstrapCycles(runtime, 5); // settle control reset sequence

  const targetAddr = readMos6502ResetVector(runtime);
  if (targetAddr == null) {
    log('MOS6502 bootstrap skipped: reset vector unavailable');
    return;
  }
  const opcode = readMos6502Byte(runtime, targetAddr);
  pokeSignalIfPresent(runtime, 'ext_pc_load_data', targetAddr);
  pokeSignalIfPresent(runtime, 'ext_pc_load_en', 1);
  pokeSignalIfPresent(runtime, 'data_in', opcode);

  if (typeof runtime.sim.has_signal === 'function'
    && runtime.sim.has_signal('clk')
    && typeof runtime.sim.evaluate === 'function'
    && typeof runtime.sim.tick === 'function'
    && typeof runtime.sim.poke === 'function') {
    runtime.sim.poke('clk', 0);
    runtime.sim.evaluate();
    runtime.sim.poke('clk', 1);
    runtime.sim.tick();
  } else {
    runBootstrapCycles(runtime, 1);
  }

  pokeSignalIfPresent(runtime, 'ext_pc_load_en', 0);
  log(`MOS6502 bootstrap complete (PC target $${targetAddr.toString(16).toUpperCase().padStart(4, '0')})`);
}

export function resolveInitializationContext({
  options = {},
  dom,
  state,
  getRunnerPreset,
  parseIrMeta,
  log = () => {}
} = {}) {
  const simJson = String(options.simJson ?? dom.irJson?.value ?? '').trim();
  if (!simJson) {
    return null;
  }

  if (dom.irJson && simJson !== String(dom.irJson.value || '').trim()) {
    dom.irJson.value = simJson;
  }

  const preset = options.preset || getRunnerPreset(dom.runnerSelect?.value || state.runnerPreset);
  const simMeta = parseIrMeta(simJson);

  let explorerSource = String(options.explorerSource ?? simJson);
  let explorerMeta = options.explorerMeta || null;
  if (!explorerMeta && explorerSource && explorerSource !== simJson) {
    try {
      explorerMeta = parseIrMeta(explorerSource);
    } catch (err) {
      log(`Explorer IR parse failed, using simulation IR: ${err.message || err}`);
    }
  }
  if (!explorerMeta) {
    explorerMeta = simMeta;
    explorerSource = simJson;
  }
  if (explorerMeta !== simMeta) {
    explorerMeta = { ...explorerMeta, liveSignalNames: simMeta.names };
  }

  return {
    simJson,
    preset,
    simMeta,
    explorerSource,
    explorerMeta
  };
}

export function resetSimulatorSession({
  runtime,
  state,
  appStore,
  storeActions,
  createSimulator,
  backend,
  simJson,
  simMeta,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  updateApple2SpeakerAudio,
  setMemoryDumpStatus,
  setMemoryResetVectorInput
} = {}) {
  if (runtime.sim) {
    runtime.sim.destroy();
  }

  runtime.sim = createSimulator(runtime.instance, simJson, backend);
  runtime.irMeta = simMeta;
  setCycleState(0);
  setUiCyclesPendingState(0);
  setRunningState(false);
  appStore.dispatch(storeActions.watchClear());
  appStore.dispatch(storeActions.breakpointClear());

  state.apple2.enabled = false;
  state.apple2.keyQueue = [];
  state.apple2.lastCpuResult = null;
  state.apple2.lastSpeakerToggles = 0;
  state.apple2.lastMappedSoundValue = null;
  state.apple2.baseRomBytes = null;
  state.apple2.ioConfig = null;
  if (runtime.throughput && typeof runtime.throughput === 'object') {
    runtime.throughput.cyclesPerSecond = 0;
    runtime.throughput.lastSampleTimeMs = null;
    runtime.throughput.lastSampleCycle = 0;
  }

  updateApple2SpeakerAudio(0, 0);
  setMemoryDumpStatus('');
  setMemoryResetVectorInput(null);
}

export function seedDefaultWatchSignals({
  runtime,
  simMeta,
  addWatchSignal,
  selectedClock
} = {}) {
  const outputs = runtime.sim.output_names();
  for (const name of outputs.slice(0, 4)) {
    addWatchSignal(name);
  }

  const clk = selectedClock();
  if (clk) {
    addWatchSignal(clk);
  } else if (simMeta.clocks.length > 0) {
    addWatchSignal(simMeta.clocks[0]);
  }
}

export async function initializeApple2Mode({
  runtime,
  state,
  preset,
  addWatchSignal,
  fetchImpl = globalThis.fetch,
  log = () => {}
} = {}) {
  const ioConfig = resolveRunnerIoConfig(preset);
  const defaultDisk = resolveDefaultDiskConfig(preset);
  const defaultBin = resolveDefaultBinConfig(preset);
  state.apple2.ioConfig = ioConfig;

  const supportsRunnerApi = runtime.sim.runner_mode?.() === true
    || (typeof runtime.sim?.runner_read_memory === 'function'
      && typeof runtime.sim?.runner_write_memory === 'function');
  const supportsGenericMemoryApi = typeof runtime.sim?.memory_mode === 'function'
    && runtime.sim.memory_mode() != null;
  const wantsMemoryApi = ioConfig.enabled || !!ioConfig.rom?.path || !!defaultDisk || !!defaultBin;

  if (!wantsMemoryApi) {
    return;
  }

  if (!supportsRunnerApi && !supportsGenericMemoryApi) {
    log(`Runner ${preset?.id || 'unknown'} requested memory-mapped features but has no supported memory API.`);
    return;
  }

  if (ioConfig.enabled) {
    state.apple2.enabled = true;
    const watchSignals = Array.isArray(ioConfig.watchSignals) && ioConfig.watchSignals.length > 0
      ? ioConfig.watchSignals
      : DEFAULT_APPLE2_WATCHES;
    for (const name of watchSignals) {
      if (runtime.sim.has_signal(name)) {
        addWatchSignal(name);
      }
    }
  }

  await loadRunnerRomAsset({
    runtime,
    state,
    ioConfig,
    supportsRunnerApi,
    supportsGenericMemoryApi,
    fetchImpl,
    log
  });

  await loadDefaultDiskAsset({
    runtime,
    defaultDisk,
    supportsRunnerApi,
    fetchImpl,
    log
  });

  await loadDefaultBinAsset({
    runtime,
    defaultBin,
    supportsRunnerApi,
    supportsGenericMemoryApi,
    fetchImpl,
    log
  });
}
