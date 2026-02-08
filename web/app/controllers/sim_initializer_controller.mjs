function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimInitializerController requires function: ${name}`);
  }
}

export function createSimInitializerController({
  dom,
  state,
  runtime,
  appStore,
  storeActions,
  parseIrMeta,
  getRunnerPreset,
  setRunnerPresetState,
  setComponentSourceBundle,
  setComponentSchematicBundle,
  ensureBackendInstance,
  createSimulator,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  updateApple2SpeakerAudio,
  setMemoryDumpStatus,
  setMemoryResetVectorInput,
  initializeTrace,
  populateClockSelect,
  addWatchSignal,
  selectedClock,
  renderWatchList,
  renderBreakpointList,
  refreshWatchTable,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  setComponentSourceOverride,
  clearComponentSourceOverride,
  rebuildComponentExplorer,
  refreshStatus,
  log,
  fetchImpl = globalThis.fetch
} = {}) {
  if (!dom || !state || !runtime || !appStore || !storeActions) {
    throw new Error('createSimInitializerController requires dom/state/runtime/appStore/storeActions');
  }
  requireFn('parseIrMeta', parseIrMeta);
  requireFn('getRunnerPreset', getRunnerPreset);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('setComponentSourceBundle', setComponentSourceBundle);
  requireFn('setComponentSchematicBundle', setComponentSchematicBundle);
  requireFn('ensureBackendInstance', ensureBackendInstance);
  requireFn('createSimulator', createSimulator);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setRunningState', setRunningState);
  requireFn('updateApple2SpeakerAudio', updateApple2SpeakerAudio);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('setMemoryResetVectorInput', setMemoryResetVectorInput);
  requireFn('initializeTrace', initializeTrace);
  requireFn('populateClockSelect', populateClockSelect);
  requireFn('addWatchSignal', addWatchSignal);
  requireFn('selectedClock', selectedClock);
  requireFn('renderWatchList', renderWatchList);
  requireFn('renderBreakpointList', renderBreakpointList);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('setComponentSourceOverride', setComponentSourceOverride);
  requireFn('clearComponentSourceOverride', clearComponentSourceOverride);
  requireFn('rebuildComponentExplorer', rebuildComponentExplorer);
  requireFn('refreshStatus', refreshStatus);
  requireFn('log', log);
  requireFn('fetchImpl', fetchImpl);

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
    setRunnerPresetState(preset.id);
    setComponentSourceBundle(options.componentSourceBundle || null);
    setComponentSchematicBundle(options.componentSchematicBundle || null);

    try {
      if (!runtime.instance) {
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

      if (runtime.sim) {
        runtime.sim.destroy();
      }

      runtime.sim = createSimulator(runtime.instance, json, state.backend);
      runtime.irMeta = meta;
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

      initializeTrace();
      populateClockSelect();

      const outputs = runtime.sim.output_names();
      for (const name of outputs.slice(0, 4)) {
        addWatchSignal(name);
      }

      const clk = selectedClock();
      if (clk) {
        addWatchSignal(clk);
      } else if (meta.clocks.length > 0) {
        addWatchSignal(meta.clocks[0]);
      }

      if (runtime.sim.apple2_mode()) {
        state.apple2.enabled = true;
        const defaultApple2Watches = ['pc_debug', 'a_debug', 'x_debug', 'y_debug', 'opcode_debug', 'speaker'];
        for (const name of defaultApple2Watches) {
          if (runtime.sim.has_signal(name)) {
            addWatchSignal(name);
          }
        }

        if (preset?.enableApple2Ui && preset.romPath) {
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

  return {
    initializeSimulator
  };
}
