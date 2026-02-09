import { formatValue } from '../../../core/lib/numeric_utils.mjs';
import { normalizeTheme, waveformFontFamily } from '../../../core/lib/theme_utils.mjs';
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
import {
  SIDEBAR_COLLAPSED_KEY,
  TERMINAL_OPEN_KEY,
  THEME_KEY
} from '../config/constants.mjs';
import { RUNNER_PRESETS } from '../../runner/config/presets.mjs';
import { BACKEND_DEFS, getBackendDef } from '../../sim/runtime/backend_defs.mjs';
import {
  DASHBOARD_ROOT_CONFIGS,
  DASHBOARD_LAYOUT_KEY,
  DASHBOARD_MIN_ROW_HEIGHT,
  createDashboardLayoutManager
} from '../managers/dashboard_layout_manager.mjs';
import {
  bindDashboardResizeEvents,
  bindDashboardPanelEvents
} from '../bindings/dashboard_bindings.mjs';
import { createTerminalCommandController } from '../../terminal/controllers/command_controller.mjs';
import { createShellStateController } from './state_controller.mjs';
import { createDashboardLayoutController } from './layout_controller.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createShellLazyGetters requires function: ${name}`);
  }
}

export function createShellLazyGetters({
  dom,
  state,
  runtime,
  scheduleReduxUxSync,
  setRunnerPresetState,
  setActiveTabState,
  setSidebarCollapsedState,
  setTerminalOpenState,
  setThemeState,
  setMemoryFollowPcState,
  replaceBreakpointsState,
  requestFrame,
  windowRef,
  documentRef,
  localStorageRef,
  eventCtor,
  currentRunnerPreset,
  setSidebarCollapsed,
  setTerminalOpen,
  setActiveTab,
  updateIrSourceVisibility,
  loadRunnerPreset,
  refreshStatus,
  applyTheme,
  loadSample,
  initializeSimulator,
  stepSimulation,
  addWatchSignal,
  removeWatchSignal,
  clearAllWatches,
  addBreakpointSignal,
  clearAllBreakpoints,
  renderBreakpointList,
  refreshMemoryView,
  resetApple2WithMemoryVectorOverride,
  loadKaratekaDump,
  loadLastSavedApple2Dump,
  saveApple2MemoryDump,
  saveApple2MemorySnapshot,
  queueApple2Key,
  refreshAllDashboardRowSizing,
  refreshComponentExplorer,
  isComponentTabActive,
  refreshActiveComponentTab
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createShellLazyGetters requires dom/state/runtime');
  }
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('setRunnerPresetState', setRunnerPresetState);
  requireFn('setActiveTabState', setActiveTabState);
  requireFn('setSidebarCollapsedState', setSidebarCollapsedState);
  requireFn('setTerminalOpenState', setTerminalOpenState);
  requireFn('setThemeState', setThemeState);
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('replaceBreakpointsState', replaceBreakpointsState);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('setSidebarCollapsed', setSidebarCollapsed);
  requireFn('setTerminalOpen', setTerminalOpen);
  requireFn('setActiveTab', setActiveTab);
  requireFn('updateIrSourceVisibility', updateIrSourceVisibility);
  requireFn('loadRunnerPreset', loadRunnerPreset);
  requireFn('refreshStatus', refreshStatus);
  requireFn('applyTheme', applyTheme);
  requireFn('loadSample', loadSample);
  requireFn('initializeSimulator', initializeSimulator);
  requireFn('stepSimulation', stepSimulation);
  requireFn('addWatchSignal', addWatchSignal);
  requireFn('removeWatchSignal', removeWatchSignal);
  requireFn('clearAllWatches', clearAllWatches);
  requireFn('addBreakpointSignal', addBreakpointSignal);
  requireFn('clearAllBreakpoints', clearAllBreakpoints);
  requireFn('renderBreakpointList', renderBreakpointList);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('resetApple2WithMemoryVectorOverride', resetApple2WithMemoryVectorOverride);
  requireFn('loadKaratekaDump', loadKaratekaDump);
  requireFn('loadLastSavedApple2Dump', loadLastSavedApple2Dump);
  requireFn('saveApple2MemoryDump', saveApple2MemoryDump);
  requireFn('saveApple2MemorySnapshot', saveApple2MemorySnapshot);
  requireFn('queueApple2Key', queueApple2Key);
  requireFn('refreshAllDashboardRowSizing', refreshAllDashboardRowSizing);
  requireFn('refreshComponentExplorer', refreshComponentExplorer);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshActiveComponentTab', refreshActiveComponentTab);

  let terminalController = null;
  let shellStateController = null;
  let dashboardLayoutController = null;

  function getTerminalController() {
    if (!terminalController) {
      terminalController = createTerminalCommandController({
        dom,
        state,
        runtime,
        backendDefs: BACKEND_DEFS,
        runnerPresets: RUNNER_PRESETS,
        actions: {
          currentRunnerPreset,
          getBackendDef,
          setSidebarCollapsed,
          setTerminalOpen,
          setActiveTab,
          setRunnerPresetState,
          updateIrSourceVisibility,
          loadRunnerPreset,
          refreshStatus,
          applyTheme,
          loadSample,
          initializeSimulator,
          stepSimulation,
          addWatchSignal,
          removeWatchSignal,
          clearAllWatches,
          addBreakpointSignal,
          clearAllBreakpoints,
          replaceBreakpointsState,
          renderBreakpointList,
          setMemoryFollowPcState,
          refreshMemoryView,
          resetApple2WithMemoryVectorOverride,
          loadKaratekaDump,
          loadLastSavedApple2Dump,
          saveApple2MemoryDump,
          saveApple2MemorySnapshot,
          queueApple2Key,
          formatValue
        },
        documentRef,
        eventCtor,
        requestFrame
      });
    }
    return terminalController;
  }

  function getShellStateController() {
    if (!shellStateController) {
      shellStateController = createShellStateController({
        dom,
        state,
        runtime,
        setActiveTabState,
        setSidebarCollapsedState,
        setTerminalOpenState,
        setThemeState,
        refreshAllDashboardRowSizing,
        refreshComponentExplorer,
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

  function getDashboardLayoutController() {
    if (!dashboardLayoutController) {
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
        isComponentTabActive,
        refreshActiveComponentTab,
        refreshMemoryView,
        getActiveTab: () => state.activeTab,
        createDashboardLayoutManager
      });
    }
    return dashboardLayoutController;
  }

  return {
    getTerminalController,
    getShellStateController,
    getDashboardLayoutController
  };
}
