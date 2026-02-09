import test from 'node:test';
import assert from 'node:assert/strict';

import { startApp } from '../../../../app/core/controllers/startup.mjs';

function createHarness(overrides = {}) {
  const calls = [];
  const registered = [];
  const bound = {
    core: null,
    component: null,
    io: null,
    sim: null,
    memory: null,
    collapsible: null
  };

  const state = {
    backend: 'compiler',
    runnerPreset: 'apple2',
    activeTab: 'ioTab'
  };

  const dom = {
    backendSelect: { value: 'compiler' },
    runnerSelect: { value: 'apple2' },
    simStatus: { textContent: '' },
    terminalOutput: { textContent: '', scrollTop: 0, scrollHeight: 0 }
  };

  const terminal = {
    writeLine: (message) => calls.push(['terminal.writeLine', message]),
    submitInput: async () => {},
    historyNavigate: () => {}
  };

  const dashboard = {
    disposeLayoutBuilder: () => calls.push(['dashboard.disposeLayoutBuilder']),
    refreshRowSizing: () => {},
    refreshAllRowSizing: () => {},
    initializeLayoutBuilder: () => calls.push(['dashboard.initializeLayoutBuilder'])
  };

  const shell = {
    setSidebarCollapsed: (value) => calls.push(['shell.setSidebarCollapsed', value]),
    setTerminalOpen: (value, opts) => calls.push(['shell.setTerminalOpen', value, opts?.persist, opts?.focus]),
    applyTheme: (value, opts) => calls.push(['shell.applyTheme', value, opts?.persist]),
    setActiveTab: (tab) => calls.push(['shell.setActiveTab', tab]),
    terminal,
    dashboard
  };

  const runnerActionsController = {
    preloadStartPreset: async (preset) => calls.push(['runner.preloadStartPreset', preset?.id || null])
  };

  const runner = {
    ensureBackendInstance: async (backend) => {
      calls.push(['runner.ensureBackendInstance', backend]);
      if (overrides.ensureBackendError) {
        throw overrides.ensureBackendError;
      }
    },
    updateIrSourceVisibility: () => calls.push(['runner.updateIrSourceVisibility']),
    currentPreset: () => ({ id: 'apple2', usesManualIr: false }),
    getActionsController: () => runnerActionsController,
    loadPreset: async () => {},
    loadBundle: async () => ({ simJson: '{}', explorerJson: '{}', explorerMeta: null }),
    getPreset: (id) => ({ id, usesManualIr: id === 'generic' }),
    loadSample: async () => {}
  };

  const apple2 = {
    updateIoToggleUi: () => calls.push(['apple2.updateIoToggleUi']),
    refreshScreen: () => calls.push(['apple2.refreshScreen']),
    refreshDebug: () => calls.push(['apple2.refreshDebug']),
    refreshMemoryView: () => calls.push(['apple2.refreshMemoryView']),
    resetWithMemoryVectorOverride: async () => true
  };

  const sim = {
    setupP5: () => calls.push(['sim.setupP5']),
    refreshStatus: () => {},
    initializeSimulator: async () => {}
  };

  const components = {
    refreshExplorer: () => {},
    isTabActive: () => false,
    refreshActiveTab: () => {}
  };

  const watch = {
    refreshTable: () => {},
    addSignal: () => true,
    removeSignal: () => true,
    clearAll: () => {},
    addBreakpoint: () => 1n,
    clearBreakpoints: () => {},
    removeBreakpoint: () => true,
    checkBreakpoints: () => null,
    renderList: () => {},
    renderBreakpoints: () => {}
  };

  const localStorageValues = {
    'test.sidebar': '1',
    'test.terminal': '1',
    'test.theme': 'original'
  };

  const localStorageRef = {
    getItem(key) {
      if (overrides.localStorageThrows) {
        throw new Error('storage unavailable');
      }
      return localStorageValues[key] ?? null;
    }
  };

  const bindings = {
    COLLAPSIBLE_PANEL_SELECTOR: '.panel',
    bindCoreBindings(args) {
      bound.core = args;
      return () => {};
    },
    bindMemoryBindings(args) {
      bound.memory = args;
      return () => {};
    },
    bindComponentBindings(args) {
      bound.component = args;
      return () => {};
    },
    bindIoBindings(args) {
      bound.io = args;
      return () => {};
    },
    bindSimBindings(args) {
      bound.sim = args;
      return () => {};
    },
    bindCollapsiblePanels(args) {
      bound.collapsible = args;
      return () => {};
    },
    registerUiBinding(fn) {
      registered.push(fn);
      calls.push(['registerUiBinding']);
    },
    disposeUiBindings() {
      calls.push(['disposeUiBindings']);
    }
  };

  const storeCalls = [];
  const store = {
    setBackendState: (value) => storeCalls.push(['setBackendState', value]),
    setRunnerPresetState: (value) => storeCalls.push(['setRunnerPresetState', value]),
    setApple2DisplayHiresState: () => {},
    setApple2DisplayColorState: () => {},
    setRunningState: () => {},
    setCycleState: () => {},
    setUiCyclesPendingState: () => {},
    setMemoryFollowPcState: () => {},
    syncReduxUxState: (reason) => storeCalls.push(['syncReduxUxState', reason]),
    scheduleReduxUxSync: () => {}
  };

  const logs = [];
  const log = (message) => {
    logs.push(String(message));
  };

  const ctx = {
    dom,
    state,
    runtime: {},
    appStore: {},
    storeActions: {},
    env: {
      localStorageRef,
      requestAnimationFrameImpl: (cb) => cb()
    },
    store,
    util: {
      getBackendDef: (id) => ({ id }),
      parseNumeric: () => null,
      parseHexOrDec: () => 0,
      hexByte: (value) => value.toString(16),
      normalizeTheme: (value) => (value === 'original' ? 'original' : 'shenzhen'),
      isSnapshotFileName: () => false
    },
    keys: {
      SIDEBAR_COLLAPSED_KEY: 'test.sidebar',
      TERMINAL_OPEN_KEY: 'test.terminal',
      THEME_KEY: 'test.theme'
    },
    bindings,
    log,
    app: {
      shell,
      runner,
      components,
      apple2,
      sim,
      watch
    }
  };

  return {
    ctx,
    calls,
    storeCalls,
    registered,
    bound,
    logs,
    dom,
    terminal
  };
}

test('startApp wires grouped shell/runner/apple2/sim/watch contracts into bindings', async () => {
  const harness = createHarness();
  const result = await startApp(harness.ctx);

  assert.equal(result, true);
  assert.deepEqual(harness.storeCalls[0], ['setBackendState', 'compiler']);
  assert.deepEqual(harness.storeCalls[1], ['setRunnerPresetState', 'apple2']);
  assert.deepEqual(harness.storeCalls[harness.storeCalls.length - 1], ['syncReduxUxState', 'start']);

  assert.equal(harness.calls.some(([name, value]) => name === 'shell.setSidebarCollapsed' && value === true), true);
  assert.equal(harness.calls.some(([name, value]) => name === 'shell.setTerminalOpen' && value === true), true);
  assert.equal(harness.calls.some(([name, value]) => name === 'shell.applyTheme' && value === 'original'), true);
  assert.equal(harness.calls.some(([name, backend]) => name === 'runner.ensureBackendInstance' && backend === 'compiler'), true);
  assert.equal(harness.calls.some(([name, tab]) => name === 'shell.setActiveTab' && tab === 'vcdTab'), true);
  assert.equal(harness.calls.some(([name]) => name === 'sim.setupP5'), true);
  assert.equal(harness.calls.some(([name, id]) => name === 'runner.preloadStartPreset' && id === 'apple2'), true);
  assert.equal(harness.calls.some(([name]) => name === 'apple2.refreshMemoryView'), true);

  assert.equal(harness.bound.core.shell.submitTerminalInput, harness.terminal.submitInput);
  assert.equal(harness.bound.sim.watch.addBreakpoint, harness.ctx.app.watch.addBreakpoint);
  assert.equal(harness.bound.memory.apple2.refreshMemoryView, harness.ctx.app.apple2.refreshMemoryView);
  assert.equal(typeof harness.bound.collapsible.actions.refreshActiveComponentTab, 'function');

  assert.equal(harness.registered.length, 7);
  assert.equal(harness.dom.simStatus.textContent, 'WASM ready (compiler)');
});

test('startApp surfaces startup failures and skips binding registration', async () => {
  const backendError = new Error('backend unavailable');
  const harness = createHarness({ ensureBackendError: backendError });

  const result = await startApp(harness.ctx);

  assert.equal(result, undefined);
  assert.match(harness.dom.simStatus.textContent, /WASM init failed: backend unavailable/);
  assert.equal(harness.logs.some((line) => /WASM init failed: backend unavailable/.test(line)), true);
  assert.equal(harness.registered.length, 0);
  assert.equal(harness.calls.some(([name]) => name === 'disposeUiBindings'), false);
});
