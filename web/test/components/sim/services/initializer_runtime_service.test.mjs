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
        runner_mode: () => true,
        has_signal: (name) => name === 'pc_debug' || name === 'speaker',
        runner_load_rom: (bytes) => {
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
  assert.equal(logs.some((line) => String(line).includes('Loaded runner ROM via runner_load_rom')), true);
});

test('initializeApple2Mode loads default bin into main memory and resets', async () => {
  const calls = [];
  await initializeApple2Mode({
    runtime: {
      sim: {
        runner_mode: () => true,
        runner_load_memory: (bytes, offset, options) => {
          calls.push(['load', bytes.length, offset, options]);
          return true;
        },
        runner_set_reset_vector: (pc) => {
          calls.push(['setPc', pc]);
          return true;
        },
        reset: () => calls.push(['reset'])
      }
    },
    state: { apple2: { enabled: false, baseRomBytes: null } },
    preset: {
      defaultBin: {
        path: '/fixtures/cpu/default.bin',
        offset: 0x200,
        space: 'main',
        startPc: '0x0200',
        resetAfterLoad: true
      }
    },
    addWatchSignal: () => {},
    fetchImpl: async () => ({
      ok: true,
      async arrayBuffer() {
        return new Uint8Array([0xA9, 0x23]).buffer;
      }
    }),
    log: () => {}
  });

  assert.deepEqual(calls, [
    ['load', 2, 0x200, { isRom: false }],
    ['setPc', 0x0200],
    ['reset']
  ]);
});

test('initializeApple2Mode loads boot ROM default bin through runner API', async () => {
  const calls = [];
  await initializeApple2Mode({
    runtime: {
      sim: {
        runner_mode: () => true,
        runner_load_boot_rom: (bytes) => {
          calls.push(['boot', bytes.length]);
          return true;
        },
        reset: () => calls.push(['reset'])
      }
    },
    state: { apple2: { enabled: false, baseRomBytes: null } },
    preset: {
      defaultBin: {
        path: '/fixtures/gameboy/dmg_boot.bin',
        space: 'boot_rom',
        resetAfterLoad: true
      }
    },
    addWatchSignal: () => {},
    fetchImpl: async () => ({
      ok: true,
      async arrayBuffer() {
        return new Uint8Array([0x31, 0xFE, 0xFF]).buffer;
      }
    }),
    log: () => {}
  });

  assert.deepEqual(calls, [
    ['boot', 3],
    ['reset']
  ]);
});

test('initializeApple2Mode loads snapshot default bin using snapshot offset and start PC', async () => {
  const calls = [];
  const snapshotPayload = {
    kind: 'rhdl.apple2.ram_snapshot',
    version: 1,
    label: 'Karateka dump (PC=$B82A)',
    offset: 0x1200,
    length: 3,
    startPc: 0xB82A,
    dataB64: 'AQID'
  };

  await initializeApple2Mode({
    runtime: {
      sim: {
        runner_mode: () => true,
        runner_load_memory: (bytes, offset, options) => {
          calls.push(['load', Array.from(bytes), offset, options]);
          return true;
        },
        runner_set_reset_vector: (pc) => {
          calls.push(['setPc', pc]);
          return true;
        },
        reset: () => calls.push(['reset'])
      }
    },
    state: { apple2: { enabled: false, baseRomBytes: null } },
    preset: {
      defaultBin: {
        path: '/fixtures/mos6502/karateka_mem.rhdlsnap',
        offset: 0,
        space: 'main',
        resetAfterLoad: true
      }
    },
    addWatchSignal: () => {},
    fetchImpl: async () => ({
      ok: true,
      async text() {
        return JSON.stringify(snapshotPayload);
      }
    }),
    log: () => {}
  });

  assert.deepEqual(calls, [
    ['load', [1, 2, 3], 0x1200, { isRom: false }],
    ['setPc', 0xB82A],
    ['reset']
  ]);
});
