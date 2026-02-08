import { html, render as litRender } from 'https://cdn.jsdelivr.net/npm/lit-html@3.2.1/+esm';
import {
  toBigInt,
  parseNumeric,
  formatValue,
  parseHexOrDec,
  hexWord,
  hexByte
} from '../lib/numeric_utils.mjs';
import { disassemble6502Lines as disassemble6502LinesWithMemory } from '../lib/mos6502_disasm.mjs';
import { normalizeTheme, waveformFontFamily } from '../lib/theme_utils.mjs';
import {
  safeSlugToken,
  normalizeDashboardSpan,
  dashboardRowSignature,
  dashboardDropPosition
} from '../lib/dashboard_utils.mjs';
import {
  parseDashboardLayouts,
  serializeDashboardLayouts,
  withDashboardRowHeight
} from '../lib/dashboard_state_utils.mjs';
import { parseIrMeta } from '../lib/ir_meta_utils.mjs';
import {
  normalizeComponentSourceBundle,
  normalizeComponentSchematicBundle
} from '../lib/bundle_utils.mjs';
import {
  renderWatchTableRows,
  renderWatchListItems,
  renderBreakpointListItems
} from '../components/vcd_panel.mjs';
import { renderApple2DebugRows } from '../components/io_panel.mjs';
import { renderMemoryPanel } from '../components/memory_panel.mjs';
import {
  DASHBOARD_ROOT_CONFIGS,
  DASHBOARD_LAYOUT_KEY,
  DASHBOARD_MIN_ROW_HEIGHT,
  createDashboardLayoutManager
} from '../managers/dashboard_layout_manager.mjs';
import { createTerminalCommandController } from './terminal_command_controller.mjs';
import { createWatchManager } from '../managers/watch_manager.mjs';
import { createSimRuntimeController } from './sim_runtime_controller.mjs';
import { createRunnerBundleLoader } from './runner_bundle_controller.mjs';
import { createRunnerActionsController } from './runner_actions_controller.mjs';
import { createSimInitializerController } from './sim_initializer_controller.mjs';
import { createSimStatusController } from './sim_status_controller.mjs';
import { createApple2MemoryController } from './apple2_memory_controller.mjs';
import { createApple2VisualController } from './apple2_visual_controller.mjs';
import { createSimLoopController } from './sim_loop_controller.mjs';
import { createComponentExplorerController } from './explorer_controller.mjs';
import { createApple2OpsController } from './apple2_ops_controller.mjs';
import { createShellStateController } from './shell_state_controller.mjs';
import { createComponentSourceController } from './source_controller.mjs';
import { createDashboardLayoutController } from './dashboard_layout_controller.mjs';
import { bindDashboardResizeEvents, bindDashboardPanelEvents } from '../bindings/dashboard_bindings.mjs';
import {
  RUNNER_PRESETS,
  APPLE2_RAM_BYTES,
  APPLE2_ADDR_SPACE,
  KARATEKA_PC,
  LAST_APPLE2_DUMP_KEY,
  SIDEBAR_COLLAPSED_KEY,
  TERMINAL_OPEN_KEY,
  THEME_KEY,
  COMPONENT_SIGNAL_PREVIEW_LIMIT
} from '../app_constants.mjs';
import { BACKEND_DEFS, getBackendDef } from '../runtime/backend_defs.mjs';
import { WasmIrSimulator } from '../runtime/wasm_ir_simulator.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createRegistryLazyGetters requires function: ${name}`);
  }
}

export function createRegistryLazyGetters(options = {}) {
  const {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    scheduleReduxUxSync,
    log,
    setRunnerPresetState,
    setActiveTabState,
    setSidebarCollapsedState,
    setTerminalOpenState,
    setThemeState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setApple2SoundEnabledState,
    replaceBreakpointsState,
    fetchImpl = globalThis.fetch,
    webAssemblyApi = globalThis.WebAssembly,
    requestFrame = globalThis.requestAnimationFrame,
    windowRef = globalThis.window,
    documentRef = globalThis.document,
    localStorageRef = globalThis.localStorage,
    eventCtor = globalThis.Event,
    getApi
  } = options;

  requireFn('getApi', getApi);

  let watchManager = null;
  let simRuntimeController = null;
  let simInitializerController = null;
  let simStatusController = null;
  let apple2MemoryController = null;
  let apple2VisualController = null;
  let simLoopController = null;
  let runnerBundleLoader = null;
  let runnerActionsController = null;
  let terminalController = null;
  let componentExplorerController = null;
  let apple2OpsController = null;
  let shellStateController = null;
  let componentSourceController = null;
  let dashboardLayoutController = null;

  function getWatchManager() {
    if (!watchManager) {
      const api = getApi();
      watchManager = createWatchManager({
        dom,
        state,
        runtime,
        appStore,
        storeActions,
        formatValue,
        parseNumeric,
        maskForWidth: api.maskForWidth,
        toBigInt,
        log,
        scheduleReduxUxSync,
        renderWatchTableRows,
        renderWatchListItems,
        renderBreakpointListItems
      });
    }
    return watchManager;
  }

  function getSimRuntimeController() {
    if (!simRuntimeController) {
      simRuntimeController = createSimRuntimeController({
        state,
        runtime,
        getBackendDef,
        fetchImpl,
        webAssemblyApi
      });
    }
    return simRuntimeController;
  }

  function getRunnerBundleLoader() {
    if (!runnerBundleLoader) {
      const api = getApi();
      runnerBundleLoader = createRunnerBundleLoader({
        dom,
        parseIrMeta,
        resetComponentExplorerState: api.resetComponentExplorerState,
        log,
        fetchImpl
      });
    }
    return runnerBundleLoader;
  }

  function getSimInitializerController() {
    if (!simInitializerController) {
      const api = getApi();
      simInitializerController = createSimInitializerController({
        dom,
        state,
        runtime,
        appStore,
        storeActions,
        parseIrMeta,
        getRunnerPreset: api.getRunnerPreset,
        setRunnerPresetState,
        setComponentSourceBundle: api.setComponentSourceBundle,
        setComponentSchematicBundle: api.setComponentSchematicBundle,
        ensureBackendInstance: api.ensureBackendInstance,
        createSimulator: (instance, json, backend) => new WasmIrSimulator(instance, json, backend),
        setCycleState,
        setUiCyclesPendingState,
        setRunningState,
        updateApple2SpeakerAudio: api.updateApple2SpeakerAudio,
        setMemoryDumpStatus: api.setMemoryDumpStatus,
        setMemoryResetVectorInput: api.setMemoryResetVectorInput,
        initializeTrace: api.initializeTrace,
        populateClockSelect: api.populateClockSelect,
        addWatchSignal: api.addWatchSignal,
        selectedClock: api.selectedClock,
        renderWatchList: api.renderWatchList,
        renderBreakpointList: api.renderBreakpointList,
        refreshWatchTable: api.refreshWatchTable,
        refreshApple2Screen: api.refreshApple2Screen,
        refreshApple2Debug: api.refreshApple2Debug,
        refreshMemoryView: api.refreshMemoryView,
        setComponentSourceOverride: api.setComponentSourceOverride,
        clearComponentSourceOverride: api.clearComponentSourceOverride,
        rebuildComponentExplorer: api.rebuildComponentExplorer,
        refreshStatus: api.refreshStatus,
        log,
        fetchImpl
      });
    }
    return simInitializerController;
  }

  function getSimStatusController() {
    if (!simStatusController) {
      const api = getApi();
      simStatusController = createSimStatusController({
        dom,
        state,
        runtime,
        getBackendDef,
        currentRunnerPreset: api.currentRunnerPreset,
        isApple2UiEnabled: api.isApple2UiEnabled,
        updateIoToggleUi: api.updateIoToggleUi,
        scheduleReduxUxSync,
        litRender,
        html
      });
    }
    return simStatusController;
  }

  function getApple2MemoryController() {
    if (!apple2MemoryController) {
      const api = getApi();
      apple2MemoryController = createApple2MemoryController({
        dom,
        state,
        runtime,
        isApple2UiEnabled: api.isApple2UiEnabled,
        parseHexOrDec,
        hexWord,
        hexByte,
        renderMemoryPanel,
        disassemble6502LinesWithMemory,
        setMemoryDumpStatus: api.setMemoryDumpStatus,
        addressSpace: APPLE2_ADDR_SPACE
      });
    }
    return apple2MemoryController;
  }

  function getApple2VisualController() {
    if (!apple2VisualController) {
      const api = getApi();
      apple2VisualController = createApple2VisualController({
        dom,
        state,
        runtime,
        isApple2UiEnabled: api.isApple2UiEnabled,
        updateIoToggleUi: api.updateIoToggleUi,
        renderApple2DebugRows,
        apple2HiresLineAddress: api.apple2HiresLineAddress
      });
    }
    return apple2VisualController;
  }

  function getSimLoopController() {
    if (!simLoopController) {
      const api = getApi();
      simLoopController = createSimLoopController({
        dom,
        state,
        runtime,
        isApple2UiEnabled: api.isApple2UiEnabled,
        refreshStatus: api.refreshStatus,
        updateApple2SpeakerAudio: api.updateApple2SpeakerAudio,
        setCycleState,
        setUiCyclesPendingState,
        setRunningState,
        selectedClock: api.selectedClock,
        checkBreakpoints: api.checkBreakpoints,
        formatValue,
        log,
        drainTrace: api.drainTrace,
        refreshWatchTable: api.refreshWatchTable,
        refreshApple2Screen: api.refreshApple2Screen,
        refreshApple2Debug: api.refreshApple2Debug,
        refreshMemoryView: api.refreshMemoryView,
        isComponentTabActive: api.isComponentTabActive,
        refreshActiveComponentTab: api.refreshActiveComponentTab,
        requestFrame
      });
    }
    return simLoopController;
  }

  function getRunnerActionsController() {
    if (!runnerActionsController) {
      const api = getApi();
      runnerActionsController = createRunnerActionsController({
        dom,
        getRunnerPreset: api.getRunnerPreset,
        setRunnerPresetState,
        updateIrSourceVisibility: api.updateIrSourceVisibility,
        loadRunnerIrBundle: api.loadRunnerIrBundle,
        initializeSimulator: api.initializeSimulator,
        clearComponentSourceOverride: api.clearComponentSourceOverride,
        resetComponentExplorerState: api.resetComponentExplorerState,
        log,
        isComponentTabActive: api.isComponentTabActive,
        refreshComponentExplorer: api.refreshComponentExplorer,
        clearComponentSourceBundle: api.clearComponentSourceBundle,
        clearComponentSchematicBundle: api.clearComponentSchematicBundle,
        setComponentSourceBundle: api.setComponentSourceBundle,
        setComponentSchematicBundle: api.setComponentSchematicBundle,
        setActiveTab: api.setActiveTab,
        refreshStatus: api.refreshStatus,
        fetchImpl
      });
    }
    return runnerActionsController;
  }

  function getTerminalController() {
    if (!terminalController) {
      const api = getApi();
      terminalController = createTerminalCommandController({
        dom,
        state,
        runtime,
        backendDefs: BACKEND_DEFS,
        runnerPresets: RUNNER_PRESETS,
        actions: {
          currentRunnerPreset: api.currentRunnerPreset,
          getBackendDef,
          setSidebarCollapsed: api.setSidebarCollapsed,
          setTerminalOpen: api.setTerminalOpen,
          setActiveTab: api.setActiveTab,
          setRunnerPresetState,
          updateIrSourceVisibility: api.updateIrSourceVisibility,
          loadRunnerPreset: api.loadRunnerPreset,
          refreshStatus: api.refreshStatus,
          applyTheme: api.applyTheme,
          loadSample: api.loadSample,
          initializeSimulator: api.initializeSimulator,
          stepSimulation: api.stepSimulation,
          addWatchSignal: api.addWatchSignal,
          removeWatchSignal: api.removeWatchSignal,
          clearAllWatches: api.clearAllWatches,
          addBreakpointSignal: api.addBreakpointSignal,
          clearAllBreakpoints: api.clearAllBreakpoints,
          replaceBreakpointsState,
          renderBreakpointList: api.renderBreakpointList,
          setMemoryFollowPcState,
          refreshMemoryView: api.refreshMemoryView,
          resetApple2WithMemoryVectorOverride: api.resetApple2WithMemoryVectorOverride,
          loadKaratekaDump: api.loadKaratekaDump,
          loadLastSavedApple2Dump: api.loadLastSavedApple2Dump,
          saveApple2MemoryDump: api.saveApple2MemoryDump,
          saveApple2MemorySnapshot: api.saveApple2MemorySnapshot,
          queueApple2Key: api.queueApple2Key,
          formatValue
        },
        documentRef,
        eventCtor,
        requestFrame
      });
    }
    return terminalController;
  }

  function getComponentExplorerController() {
    if (!componentExplorerController) {
      const api = getApi();
      componentExplorerController = createComponentExplorerController({
        dom,
        state,
        runtime,
        scheduleReduxUxSync,
        currentComponentSourceText: api.currentComponentSourceText,
        componentSignalPreviewLimit: COMPONENT_SIGNAL_PREVIEW_LIMIT
      });
    }
    return componentExplorerController;
  }

  function getApple2OpsController() {
    if (!apple2OpsController) {
      const api = getApi();
      apple2OpsController = createApple2OpsController({
        dom,
        state,
        runtime,
        APPLE2_RAM_BYTES,
        KARATEKA_PC,
        LAST_APPLE2_DUMP_KEY,
        setApple2SoundEnabledState,
        setMemoryFollowPcState,
        setCycleState,
        setUiCyclesPendingState,
        setRunningState,
        refreshApple2Screen: api.refreshApple2Screen,
        refreshApple2Debug: api.refreshApple2Debug,
        refreshMemoryView: api.refreshMemoryView,
        refreshWatchTable: api.refreshWatchTable,
        refreshStatus: api.refreshStatus,
        getApple2ProgramCounter: api.getApple2ProgramCounter,
        currentRunnerPreset: api.currentRunnerPreset,
        log,
        fetchImpl,
        windowRef,
        documentRef
      });
    }
    return apple2OpsController;
  }

  function getShellStateController() {
    if (!shellStateController) {
      const api = getApi();
      shellStateController = createShellStateController({
        dom,
        state,
        runtime,
        setActiveTabState,
        setSidebarCollapsedState,
        setTerminalOpenState,
        setThemeState,
        refreshAllDashboardRowSizing: api.refreshAllDashboardRowSizing,
        refreshComponentExplorer: api.refreshComponentExplorer,
        scheduleReduxUxSync,
        waveformFontFamily,
        normalizeTheme,
        SIDEBAR_COLLAPSED_KEY,
        TERMINAL_OPEN_KEY,
        THEME_KEY,
        localStorageRef,
        requestAnimationFrameImpl: requestFrame,
        documentRef,
        windowRef,
        eventCtor
      });
    }
    return shellStateController;
  }

  function getComponentSourceController() {
    if (!componentSourceController) {
      const api = getApi();
      componentSourceController = createComponentSourceController({
        dom,
        state,
        currentRunnerPreset: api.currentRunnerPreset,
        normalizeComponentSourceBundle,
        normalizeComponentSchematicBundle,
        destroyComponentGraph: api.destroyComponentGraph
      });
    }
    return componentSourceController;
  }

  function getDashboardLayoutController() {
    if (!dashboardLayoutController) {
      const api = getApi();
      dashboardLayoutController = createDashboardLayoutController({
        state,
        documentRef,
        windowRef,
        storage: localStorageRef,
        layoutStorageKey: DASHBOARD_LAYOUT_KEY,
        minRowHeight: DASHBOARD_MIN_ROW_HEIGHT,
        rootConfigs: DASHBOARD_ROOT_CONFIGS,
        parseDashboardLayouts,
        serializeDashboardLayouts,
        withDashboardRowHeight,
        normalizeDashboardSpan,
        safeSlugToken,
        dashboardRowSignature,
        dashboardDropPosition,
        bindDashboardResizeEvents,
        bindDashboardPanelEvents,
        isComponentTabActive: api.isComponentTabActive,
        refreshActiveComponentTab: api.refreshActiveComponentTab,
        refreshMemoryView: api.refreshMemoryView,
        getActiveTab: () => state.activeTab,
        createDashboardLayoutManager
      });
    }
    return dashboardLayoutController;
  }

  return {
    getWatchManager,
    getSimRuntimeController,
    getRunnerBundleLoader,
    getSimInitializerController,
    getSimStatusController,
    getApple2MemoryController,
    getApple2VisualController,
    getSimLoopController,
    getRunnerActionsController,
    getTerminalController,
    getComponentExplorerController,
    getApple2OpsController,
    getShellStateController,
    getComponentSourceController,
    getDashboardLayoutController
  };
}
