import { html, render as litRender } from 'https://cdn.jsdelivr.net/npm/lit-html@3.2.1/+esm';
import { formatValue } from '../../../core/lib/numeric_utils.mjs';
import { parseIrMeta } from '../../../core/lib/ir_meta_utils.mjs';
import { getBackendDef } from '../runtime/backend_defs.mjs';
import { WasmIrSimulator } from '../runtime/wasm_ir_simulator.mjs';
import { createSimRuntimeController } from './runtime_controller.mjs';
import { createSimInitializerController } from './initializer_controller.mjs';
import { createSimStatusController } from './status_controller.mjs';
import { createSimLoopController } from './loop_controller.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimLazyGetters requires function: ${name}`);
  }
}

export function createSimLazyGetters({
  dom,
  state,
  runtime,
  appStore,
  storeActions,
  scheduleReduxUxSync,
  setRunnerPresetState,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  fetchImpl,
  webAssemblyApi,
  requestFrame,
  log,
  getRunnerPreset,
  setComponentSourceBundle,
  setComponentSchematicBundle,
  ensureBackendInstance,
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
  currentRunnerPreset,
  isApple2UiEnabled,
  updateIoToggleUi,
  checkBreakpoints,
  isComponentTabActive,
  refreshActiveComponentTab,
  drainTrace
} = {}) {
  if (!dom || !state || !runtime || !appStore || !storeActions) {
    throw new Error('createSimLazyGetters requires dom/state/runtime/appStore/storeActions');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setRunningState', setRunningState);
  requireFn('fetchImpl', fetchImpl);
  requireFn('log', log);
  requireFn('getRunnerPreset', getRunnerPreset);
  requireFn('setComponentSourceBundle', setComponentSourceBundle);
  requireFn('setComponentSchematicBundle', setComponentSchematicBundle);
  requireFn('ensureBackendInstance', ensureBackendInstance);
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
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('checkBreakpoints', checkBreakpoints);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshActiveComponentTab', refreshActiveComponentTab);
  requireFn('drainTrace', drainTrace);

  let simRuntimeController = null;
  let simInitializerController = null;
  let simStatusController = null;
  let simLoopController = null;

  function getSimRuntimeController() {
    if (!simRuntimeController) {
      simRuntimeController = createSimRuntimeController({
        state,
        runtime,
        getBackendDef,
        currentRunnerPreset,
        fetchImpl,
        webAssemblyApi
      });
    }
    return simRuntimeController;
  }

  function getSimInitializerController() {
    if (!simInitializerController) {
      simInitializerController = createSimInitializerController({
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
        createSimulator: (instance, json, backend) => new WasmIrSimulator(instance, json, backend),
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
        fetchImpl
      });
    }
    return simInitializerController;
  }

  function getSimStatusController() {
    if (!simStatusController) {
      simStatusController = createSimStatusController({
        dom,
        state,
        runtime,
        getBackendDef,
        currentRunnerPreset,
        isApple2UiEnabled,
        updateIoToggleUi,
        scheduleReduxUxSync,
        litRender,
        html
      });
    }
    return simStatusController;
  }

  function getSimLoopController() {
    if (!simLoopController) {
      simLoopController = createSimLoopController({
        dom,
        state,
        runtime,
        isApple2UiEnabled,
        refreshStatus,
        updateApple2SpeakerAudio,
        setCycleState,
        setUiCyclesPendingState,
        setRunningState,
        selectedClock,
        checkBreakpoints,
        formatValue,
        log,
        drainTrace,
        refreshWatchTable,
        refreshApple2Screen,
        refreshApple2Debug,
        refreshMemoryView,
        isComponentTabActive,
        refreshActiveComponentTab,
        requestFrame
      });
    }
    return simLoopController;
  }

  return {
    getSimRuntimeController,
    getSimInitializerController,
    getSimStatusController,
    getSimLoopController
  };
}
