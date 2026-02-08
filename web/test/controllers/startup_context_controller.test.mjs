import test from 'node:test';
import assert from 'node:assert/strict';
import { createStartupContext } from '../../app/controllers/startup_context_controller.mjs';

function createControllerStubs() {
  const passthrough = () => {};
  return {
    shell: { setSidebarCollapsed: passthrough },
    runner: { loadPreset: passthrough },
    components: { refreshExplorer: passthrough },
    apple2: { loadKaratekaDump: passthrough },
    sim: { initializeSimulator: passthrough },
    watch: { refreshTable: passthrough }
  };
}

test('createStartupContext maps grouped domains and primitives', () => {
  const controllers = createControllerStubs();
  const ctx = createStartupContext({
    dom: {},
    state: {},
    runtime: {},
    appStore: {},
    storeActions: {},
    localStorageRef: {},
    requestAnimationFrameImpl: () => {},
    setBackendState: () => {},
    getBackendDef: () => ({}),
    setRunnerPresetState: () => {},
    setApple2DisplayHiresState: () => {},
    setApple2DisplayColorState: () => {},
    setRunningState: () => {},
    setCycleState: () => {},
    setUiCyclesPendingState: () => {},
    setMemoryFollowPcState: () => {},
    syncReduxUxState: () => {},
    scheduleReduxUxSync: () => {},
    parseNumeric: () => {},
    parseHexOrDec: () => {},
    hexByte: () => {},
    normalizeTheme: () => {},
    isSnapshotFileName: () => true,
    SIDEBAR_COLLAPSED_KEY: 'a',
    TERMINAL_OPEN_KEY: 'b',
    THEME_KEY: 'c',
    bindCoreBindings: () => {},
    bindMemoryBindings: () => {},
    bindComponentBindings: () => {},
    bindIoBindings: () => {},
    bindSimBindings: () => {},
    bindCollapsiblePanels: () => {},
    COLLAPSIBLE_PANEL_SELECTOR: '.x',
    registerUiBinding: () => {},
    disposeUiBindings: () => {},
    log: () => {},
    controllers
  });

  assert.equal(ctx.app.shell, controllers.shell);
  assert.equal(ctx.app.runner, controllers.runner);
  assert.equal(ctx.app.components, controllers.components);
  assert.equal(ctx.app.apple2, controllers.apple2);
  assert.equal(ctx.app.sim, controllers.sim);
  assert.equal(ctx.app.watch, controllers.watch);
  assert.equal(ctx.keys.THEME_KEY, 'c');
  assert.equal(ctx.bindings.COLLAPSIBLE_PANEL_SELECTOR, '.x');
  assert.equal(ctx.store.scheduleReduxUxSync instanceof Function, true);
});
