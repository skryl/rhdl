import test from 'node:test';
import assert from 'node:assert/strict';
import { createStartupInitializationService } from '../../../../app/core/services/startup_initialization_service';
import type { StartupInitializationServiceDeps } from '../../../../app/types/services';

type RecordedCall = [name: string, ...args: unknown[]];

interface RunnerPresetStub {
  id: string;
  autoLoadOnBoot?: boolean;
}

interface RunnerOverrides {
  ensureBackendInstance?: (value: string) => Promise<void>;
  currentPreset?: () => RunnerPresetStub;
}

interface HarnessOverrides {
  runner?: RunnerOverrides;
}

function createHarness(overrides: HarnessOverrides = {}) {
  const calls: RecordedCall[] = [];
  const state = { backend: 'compiler', runnerPreset: 'apple2' };
  const dom = {
    backendSelect: { value: 'compiler', innerHTML: '' },
    runnerSelect: { value: 'apple2', innerHTML: '' },
    simStatus: { textContent: '' },
    terminalOutput: { textContent: '' }
  };
  const shell = {
    setSidebarCollapsed: (value: boolean) => calls.push(['shell.setSidebarCollapsed', value]),
    setTerminalOpen: (value: boolean, opts: { persist?: boolean } = {}) => calls.push(['shell.setTerminalOpen', value, opts.persist]),
    applyTheme: (value: string, opts: { persist?: boolean } = {}) => calls.push(['shell.applyTheme', value, opts.persist]),
    setActiveTab: (value: string) => calls.push(['shell.setActiveTab', value])
  };
  const runner = {
    ensureBackendInstance: async (value: string) => {
      calls.push(['runner.ensureBackendInstance', value]);
    },
    updateIrSourceVisibility: () => calls.push(['runner.updateIrSourceVisibility']),
    currentPreset: () => ({ id: 'apple2' } as RunnerPresetStub),
    loadPreset: async (options: Record<string, unknown> = {}) => {
      const presetOverride = options.presetOverride as { id?: string } | undefined;
      calls.push(['runner.loadPreset', presetOverride?.id ?? null]);
    },
    getActionsController: () => ({
      preloadStartPreset: async (preset: { id?: string }) => {
        calls.push(['runner.preloadStartPreset', preset.id ?? null]);
      }
    })
  };
  const sim = {
    setupP5: () => calls.push(['sim.setupP5'])
  };
  const apple2 = {
    updateIoToggleUi: () => calls.push(['apple2.updateIoToggleUi']),
    refreshScreen: () => calls.push(['apple2.refreshScreen']),
    refreshDebug: () => calls.push(['apple2.refreshDebug']),
    refreshMemoryView: () => calls.push(['apple2.refreshMemoryView'])
  };
  const terminal = {
    writeLine: (message: unknown) => calls.push(['terminal.writeLine', message])
  };
  const storeCalls: RecordedCall[] = [];
  const store = {
    setBackendState: (value: string) => storeCalls.push(['setBackendState', value]),
    setRunnerPresetState: (value: string) => storeCalls.push(['setRunnerPresetState', value])
  };

  const service = createStartupInitializationService(({
    dom,
    state,
    store,
    util: {
      getBackendDef: (id: unknown) => ({ id: String(id) }),
      normalizeTheme: (value: unknown) => (value === 'original' ? 'original' : 'shenzhen')
    },
    keys: {
      SIDEBAR_COLLAPSED_KEY: 'sidebar',
      TERMINAL_OPEN_KEY: 'terminal',
      THEME_KEY: 'theme'
    },
    env: {
      localStorageRef: {
        getItem(key: string) {
          if (key === 'sidebar') return '1';
          if (key === 'terminal') return '1';
          if (key === 'theme') return 'original';
          return null;
        }
      }
    },
    shell,
    runner: {
      ...runner,
      ...(overrides.runner || {})
    },
    sim,
    apple2,
    terminal
  }) as unknown as Partial<StartupInitializationServiceDeps>);

  return { service, calls, storeCalls, dom };
}

test('startup initialization service initializes backend, runner, and shell defaults', async () => {
  const { service, calls, storeCalls, dom } = createHarness();
  await service.initialize();

  assert.equal(storeCalls[0][0], 'setBackendState');
  assert.equal(storeCalls[1][0], 'setRunnerPresetState');
  assert.equal(dom.simStatus.textContent, 'WASM ready (compiler)');
  assert.equal(calls.some(([name]) => name === 'runner.ensureBackendInstance'), true);
  assert.equal(calls.some(([name]) => name === 'sim.setupP5'), true);
  assert.equal(calls.some(([name]) => name === 'apple2.refreshMemoryView'), true);
});

test('startup initialization service reads shell state with storage fallback', () => {
  const { service } = createHarness();
  const saved = service.readSavedShellState();
  assert.deepEqual(saved, {
    collapsed: true,
    terminalOpen: true,
    savedTheme: 'original'
  });
});

test('startup initialization service auto-loads preset when configured', async () => {
  const { service, calls } = createHarness({
    runner: {
      currentPreset: () => ({ id: 'apple2', autoLoadOnBoot: true })
    }
  });
  await service.initialize();

  assert.equal(calls.some(([name, id]) => name === 'runner.loadPreset' && id === 'apple2'), true);
  assert.equal(calls.some(([name]) => name === 'runner.preloadStartPreset'), false);
});

test('startup initialization service hides unavailable backends from selector', async () => {
  const { service, calls, dom } = createHarness({
    runner: {
      ensureBackendInstance: async (value: string) => {
        calls.push(['runner.ensureBackendInstance', value]);
        if (value === 'jit') {
          throw new Error('jit unavailable');
        }
      }
    }
  });
  await service.initialize();

  assert.match(String(dom.backendSelect.innerHTML || ''), /value="interpreter"/);
  assert.match(String(dom.backendSelect.innerHTML || ''), /value="compiler"/);
  assert.doesNotMatch(String(dom.backendSelect.innerHTML || ''), /value="jit"/);
});
