import test from 'node:test';
import assert from 'node:assert/strict';

import { bindCoreBindings } from '../../../../app/components/shell/bindings/app_bindings';

function makeTarget(extra: Record<string, unknown> = {}) {
  return Object.assign(new EventTarget(), extra);
}

function makeDom() {
  return {
    loadRunnerBtn: makeTarget({ disabled: false }),
    runnerStatus: { textContent: 'Runner not initialized' },
    sidebarToggleBtn: makeTarget(),
    terminalToggleBtn: makeTarget(),
    terminalResizeHandle: makeTarget(),
    terminalPanel: {
      style: {},
      getBoundingClientRect: () => ({ height: 400 })
    },
    terminalOutput: makeTarget(),
    themeSelect: makeTarget({ value: 'shenzhen' }),
    backendSelect: makeTarget({ value: 'interpreter' }),
    simStatus: { textContent: '' },
    backendStatus: { textContent: '' },
    runnerSelect: makeTarget({ value: 'generic' }),
    loadSampleBtn: makeTarget(),
    sampleSelect: makeTarget({ value: '' }),
    irJson: { value: '' },
    tabButtons: []
  };
}

type BindingOverrides = { loadPresetDeferred?: boolean } & Record<string, unknown>;

function makeBindings(dom: ReturnType<typeof makeDom>, overrides: BindingOverrides = {}) {
  const state = {
    sidebarCollapsed: false,
    terminalOpen: true,
    backend: 'interpreter',
    terminal: { uartPassthrough: false }
  };

  const calls: Array<[string, ...unknown[]]> = [];
  let resolveLoad: (() => void) | undefined;
  let loadPromise: Promise<void> = Promise.resolve();

  const runner = {
    loadPreset: () => loadPromise,
    getPreset: (id: string) => ({ id, preferredBackend: '' }),
    updateIrSourceVisibility: () => calls.push(['updateIrSourceVisibility']),
    currentPreset: () => ({ usesManualIr: false }),
    ensureBackendInstance: async () => {},
    loadBundle: async () => ({
      simJson: '{}',
      explorerJson: '{}',
      explorerMeta: null,
      sourceBundle: null,
      schematicBundle: null
    }),
    loadSample: () => calls.push(['loadSample'])
  };

  const store = {
    setRunnerPresetState: (value: string) => calls.push(['setRunnerPresetState', value]),
    setBackendState: (value: string) => {
      state.backend = value;
      calls.push(['setBackendState', value]);
    }
  };

  const shell = {
    setSidebarCollapsed: () => {},
    setTerminalOpen: () => {},
    submitTerminalInput: async () => {},
    terminalHistoryNavigate: () => {},
    terminalBackspaceInput: () => {},
    terminalFocusInput: () => {},
    terminalAppendInput: () => {},
    applyTheme: () => {},
    setActiveTab: () => {}
  };

  const util = {
    getBackendDef: (id: string) => ({ id, label: id })
  };

  const base = {
    dom,
    state,
    shell,
    runner,
    sim: {
      refreshStatus: () => calls.push(['refreshStatus']),
      initializeSimulator: async () => {}
    },
    apple2: {
      queueKey: () => {},
      refreshMemoryView: () => {}
    },
    components: {
      refreshExplorer: () => {}
    },
    store,
    util,
    log: () => {}
  };

  if (overrides.loadPresetDeferred) {
    loadPromise = new Promise((resolve) => {
      resolveLoad = resolve;
    });
  }

  Object.assign(base, overrides);

  const teardown = bindCoreBindings(base);
  return { teardown, calls, state, resolveLoad };
}

test('load button shows loading state and disables while runner preset loads', async () => {
  const dom = makeDom();
  const { resolveLoad } = makeBindings(dom, { loadPresetDeferred: true });

  dom.loadRunnerBtn.dispatchEvent(new Event('click'));
  await Promise.resolve();

  assert.equal(dom.loadRunnerBtn.disabled, true);
  assert.equal(dom.runnerStatus.textContent, 'Loading...');

  assert.ok(resolveLoad);
  resolveLoad();
  await new Promise((resolve) => setTimeout(resolve, 0));
  await Promise.resolve();

  assert.equal(dom.loadRunnerBtn.disabled, false);
});

test('runner selection applies preferred backend to backend selector and store state', () => {
  const dom = makeDom();
  const calls: Array<[string, ...unknown[]]> = [];
  const { teardown } = makeBindings(dom, {
    runner: {
      loadPreset: async () => {},
      getPreset: (id: string) => ({ id, preferredBackend: 'compiler' }),
      updateIrSourceVisibility: () => calls.push(['updateIrSourceVisibility']),
      currentPreset: () => ({ usesManualIr: false }),
      ensureBackendInstance: async () => {},
      loadBundle: async () => ({
        simJson: '{}',
        explorerJson: '{}',
        explorerMeta: null,
        sourceBundle: null,
        schematicBundle: null
      }),
      loadSample: () => {}
    },
    store: {
      setRunnerPresetState: (value: string) => calls.push(['setRunnerPresetState', value]),
      setBackendState: (value: string) => calls.push(['setBackendState', value])
    },
    sim: {
      refreshStatus: () => calls.push(['refreshStatus']),
      initializeSimulator: async () => {}
    }
  });

  dom.runnerSelect.value = 'riscv';
  dom.runnerSelect.dispatchEvent(new Event('change'));

  assert.equal(dom.backendSelect.value, 'compiler');
  assert.deepEqual(calls, [
    ['setRunnerPresetState', 'riscv'],
    ['setBackendState', 'compiler'],
    ['updateIrSourceVisibility'],
    ['refreshStatus']
  ]);

  teardown();
});
