import test from 'node:test';
import assert from 'node:assert/strict';
import { createStartupBindingRegistrationService } from '../../../../app/core/services/startup_binding_registration_service.mjs';

test('startup binding registration service resets lifecycle and registers all bindings', () => {
  const calls = [];
  const registered = [];
  const service = createStartupBindingRegistrationService({
    dom: {},
    state: { activeTab: 'ioTab' },
    runtime: {},
    bindings: {
      COLLAPSIBLE_PANEL_SELECTOR: '.panel',
      bindCoreBindings: () => 'core-disposer',
      bindMemoryBindings: () => 'memory-disposer',
      bindComponentBindings: () => 'component-disposer',
      bindIoBindings: () => 'io-disposer',
      bindSimBindings: () => 'sim-disposer',
      bindEditorBindings: () => 'editor-disposer',
      bindCollapsiblePanels: () => 'collapsible-disposer',
      registerUiBinding: (fn) => registered.push(fn),
      disposeUiBindings: () => calls.push('disposeUiBindings')
    },
    app: {
      shell: {
        setSidebarCollapsed: () => {},
        setTerminalOpen: () => {},
        applyTheme: () => {},
        setActiveTab: () => {},
        terminal: {
          submitInput: () => {},
          historyNavigate: () => {}
        },
        dashboard: {
          disposeLayoutBuilder: () => calls.push('dashboard.disposeLayoutBuilder'),
          initializeLayoutBuilder: () => calls.push('dashboard.initializeLayoutBuilder'),
          refreshRowSizing: () => {},
          refreshAllRowSizing: () => {}
        }
      },
      runner: {
        loadPreset: () => {},
        ensureBackendInstance: async () => {},
        currentPreset: () => ({ id: 'apple2' }),
        loadBundle: async () => ({}),
        getPreset: (id) => ({ id }),
        updateIrSourceVisibility: () => {},
        loadSample: async () => {}
      },
      components: {
        isTabActive: () => false,
        refreshActiveTab: () => {},
        refreshExplorer: () => {}
      },
      apple2: {
        refreshMemoryView: () => {}
      },
      sim: {
        refreshStatus: () => {},
        initializeSimulator: async () => {}
      },
      watch: {}
    },
    store: {
      setRunnerPresetState: () => {},
      setBackendState: () => {},
      setApple2DisplayHiresState: () => {},
      setApple2DisplayColorState: () => {},
      setRunningState: () => {},
      setCycleState: () => {},
      setUiCyclesPendingState: () => {},
      setMemoryFollowPcState: () => {},
      scheduleReduxUxSync: () => {}
    },
    util: {
      getBackendDef: (id) => ({ id }),
      parseHexOrDec: () => 0,
      hexByte: () => '00',
      isSnapshotFileName: () => false
    },
    env: {
      requestAnimationFrameImpl: (cb) => cb()
    },
    log: () => {}
  });

  service.resetBindingLifecycle();
  service.registerBindings();

  assert.equal(calls.includes('disposeUiBindings'), true);
  assert.equal(calls.includes('dashboard.disposeLayoutBuilder'), true);
  assert.equal(calls.includes('dashboard.initializeLayoutBuilder'), true);
  assert.equal(registered.length, 8);
});
