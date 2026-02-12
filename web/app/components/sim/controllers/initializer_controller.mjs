import {
  resolveInitializationContext,
  resetSimulatorSession,
  seedDefaultWatchSignals,
  initializeApple2Mode
} from '../services/initializer_runtime_service.mjs';

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
    const initContext = resolveInitializationContext({
      options,
      dom,
      state,
      getRunnerPreset,
      parseIrMeta,
      log
    });
    if (!initContext) {
      log('No IR JSON provided');
      return;
    }
    const {
      simJson,
      preset,
      simMeta,
      explorerSource,
      explorerMeta
    } = initContext;
    setRunnerPresetState(preset.id);
    setComponentSourceBundle(options.componentSourceBundle || null);
    setComponentSchematicBundle(options.componentSchematicBundle || null);

    try {
      // Always re-resolve backend instance so runner-specific compiler wasm paths
      // (e.g. mos6502/gameboy/cpu8bit) are honored when switching presets.
      await ensureBackendInstance(state.backend);
      resetSimulatorSession({
        runtime,
        state,
        appStore,
        storeActions,
        createSimulator,
        backend: state.backend,
        simJson,
        simMeta,
        setCycleState,
        setUiCyclesPendingState,
        setRunningState,
        updateApple2SpeakerAudio,
        setMemoryDumpStatus,
        setMemoryResetVectorInput
      });

      initializeTrace();
      populateClockSelect();
      seedDefaultWatchSignals({ runtime, simMeta, addWatchSignal, selectedClock });
      await initializeApple2Mode({ runtime, state, preset, addWatchSignal, fetchImpl, log });

      renderWatchList();
      renderBreakpointList();
      refreshWatchTable();
      refreshApple2Screen();
      refreshApple2Debug();
      refreshMemoryView();
      if (explorerSource !== simJson) {
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
