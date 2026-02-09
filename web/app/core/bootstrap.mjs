import { actions as storeActions } from './state/actions.mjs';
import { createAppStore } from './state/store.mjs';
import { parseNumeric, parseHexOrDec, hexByte } from './lib/numeric_utils.mjs';
import { isSnapshotFileName } from '../components/apple2/lib/snapshot.mjs';
import { normalizeTheme } from './lib/theme_utils.mjs';
import { createRuntimeContext } from './runtime/context.mjs';
import { bindCoreBindings } from '../components/shell/bindings/app_bindings.mjs';
import { bindMemoryBindings } from '../components/memory/bindings/bindings.mjs';
import { bindComponentBindings } from '../components/explorer/bindings/bindings.mjs';
import { bindIoBindings } from '../components/apple2/bindings/bindings.mjs';
import { bindSimBindings } from '../components/sim/bindings/bindings.mjs';
import { bindCollapsiblePanels } from '../components/shell/bindings/collapsible_bindings.mjs';
import { startApp } from './controllers/startup.mjs';
import { createStoreDispatchers, createReduxSyncHelpers, installReduxGlobals } from './state/store_bridge.mjs';
import { createDomRefs } from './bindings/dom.mjs';
import { createInitialState } from './state/initial_state.mjs';
import { createUiBindingRegistry } from './bindings/ui_registry.mjs';
import {
  REDUX_STORE_GLOBAL_KEY,
  REDUX_SYNC_GLOBAL_KEY,
  REDUX_STATE_GLOBAL_KEY
} from './app_constants.mjs';
import {
  COLLAPSIBLE_PANEL_SELECTOR,
  SIDEBAR_COLLAPSED_KEY,
  TERMINAL_OPEN_KEY,
  THEME_KEY
} from '../components/shell/config/constants.mjs';
import { getBackendDef } from '../components/sim/runtime/backend_defs.mjs';
import { LiveVcdParser } from '../components/sim/runtime/live_vcd_parser.mjs';
import { createControllerRegistry } from './controllers/registry.mjs';
import { createEventLogger } from '../components/watch/lib/event_logger.mjs';

export function startMainApp() {
  const dom = createDomRefs(document);
  const runtime = createRuntimeContext(() => new LiveVcdParser());
  const state = createInitialState();
  const appStore = createAppStore(state, window.Redux);
  const { registerUiBinding, disposeUiBindings } = createUiBindingRegistry(runtime);

  const {
    setBackendState,
    setThemeState,
    setRunnerPresetState,
    setActiveTabState,
    setSidebarCollapsedState,
    setTerminalOpenState,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    setMemoryFollowPcState,
    setApple2DisplayHiresState,
    setApple2DisplayColorState,
    setApple2SoundEnabledState,
    replaceBreakpointsState
  } = createStoreDispatchers({ appStore, storeActions });

  const { syncReduxUxState, scheduleReduxUxSync } = createReduxSyncHelpers({ appStore, storeActions });

  installReduxGlobals({
    windowRef: window,
    appStore,
    syncReduxUxState,
    storeKey: REDUX_STORE_GLOBAL_KEY,
    stateKey: REDUX_STATE_GLOBAL_KEY,
    syncKey: REDUX_SYNC_GLOBAL_KEY
  });

  const log = createEventLogger(dom.eventLog);

  const controllers = createControllerRegistry({
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
    fetchImpl: fetch,
    webAssemblyApi: WebAssembly,
    requestFrame: requestAnimationFrame,
    windowRef: window,
    documentRef: document,
    localStorageRef: localStorage,
    eventCtor: Event,
    p5Ctor: p5
  });

  return startApp({
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    env: {
      localStorageRef: localStorage,
      requestAnimationFrameImpl: requestAnimationFrame
    },
    store: {
      setBackendState,
      setRunnerPresetState,
      setApple2DisplayHiresState,
      setApple2DisplayColorState,
      setRunningState,
      setCycleState,
      setUiCyclesPendingState,
      setMemoryFollowPcState,
      syncReduxUxState,
      scheduleReduxUxSync
    },
    util: {
      getBackendDef,
      parseNumeric,
      parseHexOrDec,
      hexByte,
      normalizeTheme,
      isSnapshotFileName
    },
    keys: {
      SIDEBAR_COLLAPSED_KEY,
      TERMINAL_OPEN_KEY,
      THEME_KEY
    },
    bindings: {
      bindCoreBindings,
      bindMemoryBindings,
      bindComponentBindings,
      bindIoBindings,
      bindSimBindings,
      bindCollapsiblePanels,
      COLLAPSIBLE_PANEL_SELECTOR,
      registerUiBinding,
      disposeUiBindings
    },
    log,
    app: controllers
  });
}
