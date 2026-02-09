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
  state.apple2.baseRomBytes = null;

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
  if (!runtime.sim.apple2_mode()) {
    return;
  }

  state.apple2.enabled = true;
  for (const name of DEFAULT_APPLE2_WATCHES) {
    if (runtime.sim.has_signal(name)) {
      addWatchSignal(name);
    }
  }

  if (!(preset?.enableApple2Ui && preset.romPath)) {
    return;
  }

  try {
    const romResp = await fetchImpl(preset.romPath);
    if (romResp.ok) {
      const romBytes = new Uint8Array(await romResp.arrayBuffer());
      state.apple2.baseRomBytes = new Uint8Array(romBytes);
      runtime.sim.apple2_load_rom(romBytes);
      log(`Loaded Apple II ROM: ${preset.romPath}`);
    } else {
      log(`Apple II ROM load skipped (${romResp.status})`);
    }
  } catch (err) {
    log(`Failed to load Apple II ROM: ${err.message || err}`);
  }
}
