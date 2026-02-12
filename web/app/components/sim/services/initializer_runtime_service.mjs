import { resolveRunnerIoConfig } from '../../runner/lib/io_config.mjs';

const DEFAULT_APPLE2_WATCHES = ['pc_debug', 'a_debug', 'x_debug', 'y_debug', 'opcode_debug', 'speaker'];
const U16_MASK = 0xFFFF;

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
  return parsed & U16_MASK;
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
    resetAfterLoad: raw.resetAfterLoad !== false
  };
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

    const bytes = new Uint8Array(await binResp.arrayBuffer());
    let loaded = false;

    if (defaultBin.space === 'boot_rom') {
      if (supportsRunnerApi && typeof runtime.sim.runner_load_boot_rom === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_boot_rom(bytes));
      }
    } else if (defaultBin.space === 'rom') {
      if (supportsRunnerApi && typeof runtime.sim.runner_load_rom === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_rom(bytes, defaultBin.offset));
      } else if (supportsRunnerApi && typeof runtime.sim.runner_load_memory === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_memory(bytes, defaultBin.offset, { isRom: true }));
      } else if (supportsGenericMemoryApi && typeof runtime.sim.memory_load === 'function') {
        loaded = didCallSucceed(runtime.sim.memory_load(bytes, defaultBin.offset, { isRom: true }));
      }
    } else {
      if (supportsRunnerApi && typeof runtime.sim.runner_load_memory === 'function') {
        loaded = didCallSucceed(runtime.sim.runner_load_memory(bytes, defaultBin.offset, { isRom: false }));
      } else if (supportsGenericMemoryApi && typeof runtime.sim.memory_load === 'function') {
        loaded = didCallSucceed(runtime.sim.memory_load(bytes, defaultBin.offset, { isRom: false }));
      }
    }

    if (!loaded) {
      log(`Default bin load failed or unsupported for space "${defaultBin.space}": ${defaultBin.path}`);
      return false;
    }

    if (defaultBin.startPc != null && typeof runtime.sim.runner_set_reset_vector === 'function') {
      const pcApplied = didCallSucceed(runtime.sim.runner_set_reset_vector(defaultBin.startPc));
      if (!pcApplied) {
        log(`Default bin reset vector apply failed (PC=$${defaultBin.startPc.toString(16).padStart(4, '0')})`);
      }
    }

    if (defaultBin.resetAfterLoad && typeof runtime.sim.reset === 'function') {
      runtime.sim.reset();
    }

    log(`Loaded default bin (${defaultBin.space}) @ 0x${defaultBin.offset.toString(16)}: ${defaultBin.path}`);
    return true;
  } catch (err) {
    log(`Failed to load default bin: ${err.message || err}`);
    return false;
  }
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
  const defaultBin = resolveDefaultBinConfig(preset);
  state.apple2.ioConfig = ioConfig;

  const supportsRunnerApi = runtime.sim.runner_mode?.() === true;
  const supportsGenericMemoryApi = typeof runtime.sim.memory_mode === 'function' && runtime.sim.memory_mode() != null;
  const wantsMemoryApi = ioConfig.enabled || !!ioConfig.rom?.path || !!defaultBin;

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

  await loadDefaultBinAsset({
    runtime,
    defaultBin,
    supportsRunnerApi,
    supportsGenericMemoryApi,
    fetchImpl,
    log
  });
}
