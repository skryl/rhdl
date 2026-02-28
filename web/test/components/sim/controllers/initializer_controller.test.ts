import test from 'node:test';
import assert from 'node:assert/strict';

import { createSimInitializerController } from '../../../../app/components/sim/controllers/initializer_controller';

function createHarness(overrides: any = {}) {
  const calls: any[] = [];
  const state = {
    backend: 'compiler',
    runnerPreset: 'generic',
    apple2: {
      enabled: true,
      keyQueue: [1, 2],
      lastCpuResult: { x: 1 },
      lastSpeakerToggles: 9,
      baseRomBytes: new Uint8Array([1, 2, 3])
    }
  };
  const runtime = {
    instance: {},
    irMeta: null,
    sim: null
  };
  const dom = {
    irJson: { value: '' },
    runnerSelect: { value: 'generic' }
  };
  const storeActions = {
    watchClear: () => ({ type: 'watchClear' }),
    breakpointClear: () => ({ type: 'breakpointClear' })
  };
  const appStore = {
    dispatch(action: any) {
      calls.push(['dispatch', action.type]);
    }
  };
  const base = {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    parseIrMeta: (text: any) => ({ names: ['clk'], clocks: ['clk'], parsedFrom: text }),
    getRunnerPreset: () => ({ id: 'generic', usesManualIr: true, enableApple2Ui: false }),
    setRunnerPresetState: (value: any) => calls.push(['setRunnerPresetState', value]),
    setComponentSourceBundle: (value: any) => calls.push(['setComponentSourceBundle', value]),
    setComponentSchematicBundle: (value: any) => calls.push(['setComponentSchematicBundle', value]),
    ensureBackendInstance: async () => {},
    createSimulator: () => ({
      output_names: () => ['out1', 'out2'],
      runner_mode: () => false
    }),
    setCycleState: (value: any) => calls.push(['setCycleState', value]),
    setUiCyclesPendingState: (value: any) => calls.push(['setUiCyclesPendingState', value]),
    setRunningState: (value: any) => calls.push(['setRunningState', value]),
    updateApple2SpeakerAudio: (...args: any[]) => calls.push(['updateApple2SpeakerAudio', ...args]),
    setMemoryDumpStatus: (value: any) => calls.push(['setMemoryDumpStatus', value]),
    setMemoryResetVectorInput: (value: any) => calls.push(['setMemoryResetVectorInput', value]),
    initializeTrace: (options: any) => calls.push(['initializeTrace', options]),
    populateClockSelect: () => calls.push(['populateClockSelect']),
    addWatchSignal: (name: any) => calls.push(['addWatchSignal', name]),
    selectedClock: () => null,
    renderWatchList: () => calls.push(['renderWatchList']),
    renderBreakpointList: () => calls.push(['renderBreakpointList']),
    refreshWatchTable: () => calls.push(['refreshWatchTable']),
    refreshApple2Screen: () => calls.push(['refreshApple2Screen']),
    refreshApple2Debug: () => calls.push(['refreshApple2Debug']),
    refreshMemoryView: () => calls.push(['refreshMemoryView']),
    setComponentSourceOverride: (...args: any[]) => calls.push(['setComponentSourceOverride', ...args]),
    clearComponentSourceOverride: () => calls.push(['clearComponentSourceOverride']),
    rebuildComponentExplorer: (...args: any[]) => calls.push(['rebuildComponentExplorer', ...args]),
    refreshStatus: () => calls.push(['refreshStatus']),
    log: (msg: any) => calls.push(['log', msg]),
    fetchImpl: async () => ({ ok: true, status: 200, async arrayBuffer() { return new ArrayBuffer(0); } })
  };
  const controller = createSimInitializerController({
    ...base,
    ...overrides
  });
  return { controller, calls, state, runtime, dom };
}

test('initializeSimulator logs when IR is missing', async () => {
  const { controller, calls } = createHarness();
  await controller.initializeSimulator({});
  assert.deepEqual(calls, [['log', 'No IR JSON provided']]);
});

test('initializeSimulator configures runtime and resets state', async () => {
  const existingDestroyCalls: any[] = [];
  const { controller, calls, runtime, state, dom } = createHarness({
    createSimulator: () => ({
      output_names: () => ['out_a', 'out_b'],
      runner_mode: () => false
    })
  });
  runtime.sim = {
    destroy: () => existingDestroyCalls.push('destroyed')
  } as any;
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({});

  assert.deepEqual(existingDestroyCalls, ['destroyed']);
  assert.equal(!!runtime.sim, true);
  assert.equal(!!runtime.irMeta, true);
  assert.equal(state.apple2.enabled, false);
  assert.deepEqual(state.apple2.keyQueue, []);
  assert.equal(calls.some(([k, v]) => k === 'setCycleState' && v === 0), true);
  assert.equal(calls.some(([k, v]) => k === 'setRunningState' && v === false), true);
  assert.equal(calls.some(([k, options]) => k === 'initializeTrace' && options?.enabled === false), true);
  assert.equal(calls.some(([k]) => k === 'populateClockSelect'), true);
  assert.equal(calls.some(([k]) => k === 'renderWatchList'), true);
  assert.equal(calls.some(([k]) => k === 'refreshStatus'), true);
  assert.equal(calls.some(([k, v]) => k === 'log' && v === 'Simulator initialized'), true);
});

test('initializeSimulator enables tracing on load when preset requests it', async () => {
  const { controller, calls, dom } = createHarness({
    getRunnerPreset: () => ({
      id: 'generic',
      usesManualIr: true,
      enableApple2Ui: false,
      traceEnabledOnLoad: true
    })
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({});

  assert.equal(calls.some(([k, options]) => k === 'initializeTrace' && options?.enabled === true), true);
});

test('initializeSimulator honors defaults.traceEnabled when present', async () => {
  const { controller, calls, dom } = createHarness({
    getRunnerPreset: () => ({
      id: 'generic',
      usesManualIr: true,
      enableApple2Ui: false,
      defaults: { traceEnabled: true }
    })
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({});

  assert.equal(calls.some(([k, options]) => k === 'initializeTrace' && options?.enabled === true), true);
});

test('initializeSimulator always refreshes backend instance for current preset/backend', async () => {
  const backendCalls: any[] = [];
  const { controller, dom } = createHarness({
    ensureBackendInstance: async (backend: any) => {
      backendCalls.push(backend);
    }
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({});

  assert.deepEqual(backendCalls, ['compiler']);
});

test('initializeSimulator yields to UI before backend/session initialization when requested', async () => {
  const { controller, calls, dom } = createHarness({
    requestFrame: (cb: any) => {
      calls.push(['requestFrame']);
      cb();
    },
    setTimeoutImpl: (cb: any) => {
      calls.push(['setTimeout']);
      cb();
    },
    ensureBackendInstance: async () => {
      calls.push(['ensureBackendInstance']);
    }
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({ yieldToUi: true });

  const firstFrameIdx = calls.findIndex(([k]) => k === 'requestFrame');
  const backendIdx = calls.findIndex(([k]) => k === 'ensureBackendInstance');
  assert.notEqual(firstFrameIdx, -1);
  assert.notEqual(backendIdx, -1);
  assert.equal(firstFrameIdx < backendIdx, true);
});

test('initializeSimulator defers component explorer rebuild when requested', async () => {
  const { controller, calls, dom } = createHarness({
    setTimeoutImpl: () => 1
  });
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({ deferComponentExplorerRebuild: true });

  assert.equal(calls.some(([k]) => k === 'rebuildComponentExplorer'), false);
});
