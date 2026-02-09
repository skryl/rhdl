import test from 'node:test';
import assert from 'node:assert/strict';

import { createSimInitializerController } from '../../../../app/components/sim/controllers/initializer_controller.mjs';

function createHarness(overrides = {}) {
  const calls = [];
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
    dispatch(action) {
      calls.push(['dispatch', action.type]);
    }
  };
  const base = {
    dom,
    state,
    runtime,
    appStore,
    storeActions,
    parseIrMeta: (text) => ({ names: ['clk'], clocks: ['clk'], parsedFrom: text }),
    getRunnerPreset: () => ({ id: 'generic', usesManualIr: true, enableApple2Ui: false }),
    setRunnerPresetState: (value) => calls.push(['setRunnerPresetState', value]),
    setComponentSourceBundle: (value) => calls.push(['setComponentSourceBundle', value]),
    setComponentSchematicBundle: (value) => calls.push(['setComponentSchematicBundle', value]),
    ensureBackendInstance: async () => {},
    createSimulator: () => ({
      output_names: () => ['out1', 'out2'],
      apple2_mode: () => false
    }),
    setCycleState: (value) => calls.push(['setCycleState', value]),
    setUiCyclesPendingState: (value) => calls.push(['setUiCyclesPendingState', value]),
    setRunningState: (value) => calls.push(['setRunningState', value]),
    updateApple2SpeakerAudio: (...args) => calls.push(['updateApple2SpeakerAudio', ...args]),
    setMemoryDumpStatus: (value) => calls.push(['setMemoryDumpStatus', value]),
    setMemoryResetVectorInput: (value) => calls.push(['setMemoryResetVectorInput', value]),
    initializeTrace: () => calls.push(['initializeTrace']),
    populateClockSelect: () => calls.push(['populateClockSelect']),
    addWatchSignal: (name) => calls.push(['addWatchSignal', name]),
    selectedClock: () => null,
    renderWatchList: () => calls.push(['renderWatchList']),
    renderBreakpointList: () => calls.push(['renderBreakpointList']),
    refreshWatchTable: () => calls.push(['refreshWatchTable']),
    refreshApple2Screen: () => calls.push(['refreshApple2Screen']),
    refreshApple2Debug: () => calls.push(['refreshApple2Debug']),
    refreshMemoryView: () => calls.push(['refreshMemoryView']),
    setComponentSourceOverride: (...args) => calls.push(['setComponentSourceOverride', ...args]),
    clearComponentSourceOverride: () => calls.push(['clearComponentSourceOverride']),
    rebuildComponentExplorer: (...args) => calls.push(['rebuildComponentExplorer', ...args]),
    refreshStatus: () => calls.push(['refreshStatus']),
    log: (msg) => calls.push(['log', msg]),
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
  const existingDestroyCalls = [];
  const { controller, calls, runtime, state, dom } = createHarness({
    createSimulator: () => ({
      output_names: () => ['out_a', 'out_b'],
      apple2_mode: () => false
    })
  });
  runtime.sim = {
    destroy: () => existingDestroyCalls.push('destroyed')
  };
  dom.irJson.value = '{"ports":[{"name":"clk","width":1}]}';

  await controller.initializeSimulator({});

  assert.deepEqual(existingDestroyCalls, ['destroyed']);
  assert.equal(!!runtime.sim, true);
  assert.equal(!!runtime.irMeta, true);
  assert.equal(state.apple2.enabled, false);
  assert.deepEqual(state.apple2.keyQueue, []);
  assert.equal(calls.some(([k, v]) => k === 'setCycleState' && v === 0), true);
  assert.equal(calls.some(([k, v]) => k === 'setRunningState' && v === false), true);
  assert.equal(calls.some(([k]) => k === 'initializeTrace'), true);
  assert.equal(calls.some(([k]) => k === 'populateClockSelect'), true);
  assert.equal(calls.some(([k]) => k === 'renderWatchList'), true);
  assert.equal(calls.some(([k]) => k === 'refreshStatus'), true);
  assert.equal(calls.some(([k, v]) => k === 'log' && v === 'Simulator initialized'), true);
});
