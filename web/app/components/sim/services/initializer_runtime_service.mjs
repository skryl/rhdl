import { resolveRunnerIoConfig } from '../../runner/lib/io_config.mjs';

const DEFAULT_APPLE2_WATCHES = ['pc_debug', 'a_debug', 'x_debug', 'y_debug', 'opcode_debug', 'speaker'];

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
  state.apple2.ioConfig = ioConfig;

  if (!ioConfig.enabled) {
    return;
  }

  const supportsRunnerApi = runtime.sim.runner_mode?.() === true;
  const supportsGenericMemoryApi = typeof runtime.sim.memory_mode === 'function' && runtime.sim.memory_mode() != null;
  if (!supportsRunnerApi && !supportsGenericMemoryApi) {
    log(`Runner ${preset?.id || 'unknown'} requested IO UI but has no supported memory API.`);
    return;
  }

  state.apple2.enabled = true;
  const watchSignals = Array.isArray(ioConfig.watchSignals) && ioConfig.watchSignals.length > 0
    ? ioConfig.watchSignals
    : DEFAULT_APPLE2_WATCHES;
  for (const name of watchSignals) {
    if (runtime.sim.has_signal(name)) {
      addWatchSignal(name);
    }
  }

  if (!ioConfig.rom?.path) {
    return;
  }

  try {
    const romResp = await fetchImpl(ioConfig.rom.path);
    if (romResp.ok) {
      const romBytes = new Uint8Array(await romResp.arrayBuffer());
      state.apple2.baseRomBytes = new Uint8Array(romBytes);
      if (supportsRunnerApi && typeof runtime.sim.runner_load_rom === 'function') {
        runtime.sim.runner_load_rom(romBytes, ioConfig.rom.offset || 0);
        log(`Loaded runner ROM via runner_load_rom: ${ioConfig.rom.path}`);
      } else if (supportsGenericMemoryApi && typeof runtime.sim.memory_load === 'function') {
        runtime.sim.memory_load(romBytes, ioConfig.rom.offset || 0, { isRom: !!ioConfig.rom.isRom });
        log(`Loaded runner ROM: ${ioConfig.rom.path}`);
      }
    } else {
      log(`Runner ROM load skipped (${romResp.status})`);
    }
  } catch (err) {
    log(`Failed to load runner ROM: ${err.message || err}`);
  }
}
