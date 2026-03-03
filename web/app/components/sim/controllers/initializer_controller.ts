import {
  resolveInitializationContext,
  resetSimulatorSession,
  seedDefaultWatchSignals,
  initializeApple2Mode
} from '../services/initializer_runtime_service';

function requireFn(name: Unsafe, fn: Unsafe) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimInitializerController requires function: ${name}`);
  }
}

function resolveTraceEnabledOnLoad(preset: Unsafe = null) {
  if (!preset || typeof preset !== 'object') {
    return false;
  }
  if (Object.prototype.hasOwnProperty.call(preset, 'traceEnabledOnLoad')) {
    return preset.traceEnabledOnLoad === true;
  }
  const defaults = preset.defaults;
  if (defaults && typeof defaults === 'object' && Object.prototype.hasOwnProperty.call(defaults, 'traceEnabled')) {
    return defaults.traceEnabled === true;
  }
  return false;
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
  fetchImpl = globalThis.fetch,
  requestFrame = globalThis.requestAnimationFrame,
  setTimeoutImpl = globalThis.setTimeout
}: Unsafe = {}) {
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

  async function waitForUiPaint() {
    await new Promise<void>((resolve) => {
      let settled = false;
      const finish = () => {
        if (settled) {
          return;
        }
        settled = true;
        resolve();
      };
      const fallbackTimer = (typeof globalThis.setTimeout === 'function')
        ? globalThis.setTimeout(finish, 120)
        : null;
      const finishWithFallbackClear = () => {
        if (fallbackTimer != null && typeof globalThis.clearTimeout === 'function') {
          globalThis.clearTimeout(fallbackTimer);
        }
        finish();
      };
      if (typeof requestFrame === 'function') {
        requestFrame(() => {
          if (typeof setTimeoutImpl === 'function') {
            setTimeoutImpl(finishWithFallbackClear, 0);
          } else {
            finishWithFallbackClear();
          }
        });
        return;
      }
      if (typeof setTimeoutImpl === 'function') {
        setTimeoutImpl(finishWithFallbackClear, 0);
        return;
      }
      finishWithFallbackClear();
    });
  }

  async function initializeSimulator(options: Unsafe = {}) {
    const shouldYieldToUi = options.yieldToUi === true;
    const deferComponentExplorerRebuild = options.deferComponentExplorerRebuild === true;
    const transferChunkBytes = Number.parseInt(options.transferChunkBytes, 10);
    const parsedChunkBytes = Number.isFinite(transferChunkBytes) && transferChunkBytes > 0
      ? transferChunkBytes
      : undefined;
    if (shouldYieldToUi) {
      await waitForUiPaint();
    }
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
    if (shouldYieldToUi) {
      await waitForUiPaint();
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
      if (shouldYieldToUi) {
        await waitForUiPaint();
      }
      // Always re-resolve backend instance so runner-specific compiler wasm paths
      // (e.g. mos6502/gameboy/cpu8bit) are honored when switching presets.
      await ensureBackendInstance(state.backend);
      if (shouldYieldToUi) {
        await waitForUiPaint();
      }
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
      if (shouldYieldToUi) {
        await waitForUiPaint();
      }

    initializeTrace({ enabled: true });
      populateClockSelect();
      seedDefaultWatchSignals({ runtime, simMeta, addWatchSignal, selectedClock });
      await initializeApple2Mode({
        runtime,
        state,
        preset,
        addWatchSignal,
        transferChunkBytes: parsedChunkBytes,
        yieldControl: shouldYieldToUi ? waitForUiPaint : null,
        fetchImpl,
        log
      });

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
      if (!deferComponentExplorerRebuild) {
        rebuildComponentExplorer(explorerMeta, explorerSource);
      }
      refreshStatus();
      log('Simulator initialized');
    } catch (err) {
      log(`Initialization failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  return {
    initializeSimulator
  };
}
