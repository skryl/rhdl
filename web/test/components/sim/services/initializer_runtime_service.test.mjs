import test from 'node:test';
import assert from 'node:assert/strict';

import {
  resolveInitializationContext,
  resetSimulatorSession,
  seedDefaultWatchSignals,
  initializeApple2Mode
} from '../../../../app/components/sim/services/initializer_runtime_service.mjs';

test('resolveInitializationContext returns null when sim json is missing', () => {
  const context = resolveInitializationContext({
    options: {},
    dom: { irJson: { value: '' }, runnerSelect: { value: 'generic' } },
    state: { runnerPreset: 'generic' },
    getRunnerPreset: () => ({ id: 'generic' }),
    parseIrMeta: () => ({ names: [], clocks: [] }),
    log: () => {}
  });
  assert.equal(context, null);
});

test('resolveInitializationContext normalizes explorer metadata', () => {
  const parseCalls = [];
  const context = resolveInitializationContext({
    options: { simJson: '{"a":1}', explorerSource: '{"b":2}' },
    dom: { irJson: { value: '' }, runnerSelect: { value: 'generic' } },
    state: { runnerPreset: 'generic' },
    getRunnerPreset: () => ({ id: 'generic' }),
    parseIrMeta: (text) => {
      parseCalls.push(text);
      return text.includes('"a":1') ? { names: ['clk'], clocks: ['clk'] } : { names: ['x'], clocks: [] };
    },
    log: () => {}
  });
  assert.equal(context.preset.id, 'generic');
  assert.equal(context.explorerSource, '{"b":2}');
  assert.deepEqual(parseCalls, ['{"a":1}', '{"b":2}']);
  assert.deepEqual(context.explorerMeta.liveSignalNames, ['clk']);
});

test('resetSimulatorSession resets runtime and apple2 state', () => {
  const calls = [];
  const state = {
    apple2: {
      enabled: true,
      keyQueue: [1],
      lastCpuResult: { ok: true },
      lastSpeakerToggles: 10,
      baseRomBytes: new Uint8Array([1])
    }
  };
  const runtime = {
    instance: {},
    sim: {
      destroy: () => calls.push('destroy')
    },
    irMeta: null
  };
  resetSimulatorSession({
    runtime,
    state,
    appStore: {
      dispatch: (action) => calls.push(action.type)
    },
    storeActions: {
      watchClear: () => ({ type: 'watchClear' }),
      breakpointClear: () => ({ type: 'breakpointClear' })
    },
    createSimulator: () => ({ created: true }),
    backend: 'compiler',
    simJson: '{}',
    simMeta: { names: [], clocks: [] },
    setCycleState: (value) => calls.push(`cycle:${value}`),
    setUiCyclesPendingState: (value) => calls.push(`pending:${value}`),
    setRunningState: (value) => calls.push(`running:${value}`),
    updateApple2SpeakerAudio: () => calls.push('speaker'),
    setMemoryDumpStatus: (value) => calls.push(`dump:${value}`),
    setMemoryResetVectorInput: (value) => calls.push(`vector:${value}`)
  });

  assert.equal(runtime.sim.created, true);
  assert.equal(state.apple2.enabled, false);
  assert.deepEqual(state.apple2.keyQueue, []);
  assert.equal(calls.includes('watchClear'), true);
  assert.equal(calls.includes('breakpointClear'), true);
});

test('seedDefaultWatchSignals adds outputs and selected clock', () => {
  const seen = [];
  seedDefaultWatchSignals({
    runtime: {
      sim: {
        output_names: () => ['a', 'b', 'c', 'd', 'e']
      }
    },
    simMeta: { clocks: ['clk'] },
    addWatchSignal: (name) => seen.push(name),
    selectedClock: () => 'clk_user'
  });
  assert.deepEqual(seen, ['a', 'b', 'c', 'd', 'clk_user']);
});

test('initializeApple2Mode loads rom when preset enables ui', async () => {
  const logs = [];
  const state = { apple2: { enabled: false, baseRomBytes: null } };
  const loaded = [];
  await initializeApple2Mode({
    runtime: {
      sim: {
        apple2_mode: () => true,
        has_signal: (name) => name === 'pc_debug' || name === 'speaker',
        apple2_load_rom: (bytes) => {
          loaded.push(bytes.length);
        }
      }
    },
    state,
    preset: { enableApple2Ui: true, romPath: '/rom.bin' },
    addWatchSignal: (name) => logs.push(`watch:${name}`),
    fetchImpl: async () => ({ ok: true, async arrayBuffer() { return new Uint8Array([1, 2, 3]).buffer; } }),
    log: (message) => logs.push(message)
  });
  assert.equal(state.apple2.enabled, true);
  assert.deepEqual(loaded, [3]);
  assert.equal(logs.some((line) => String(line).includes('Loaded Apple II ROM')), true);
});
