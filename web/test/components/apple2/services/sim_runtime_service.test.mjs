import test from 'node:test';
import assert from 'node:assert/strict';
import { createApple2SimRuntimeService } from '../../../../app/components/apple2/services/sim_runtime_service.mjs';

test('apple2 sim runtime service performs reset sequence through reset signal', () => {
  const calls = [];
  const state = { apple2: { keyQueue: [1, 2, 3] } };
  const runtime = {
    sim: {
      has_signal: (name) => name === 'reset',
      poke: (name, value) => calls.push(['poke', name, value]),
      runner_run_cycles: (count) => calls.push(['cycles', count]),
      reset: () => calls.push(['reset']),
      trace_enabled: () => true,
      trace_capture: () => calls.push(['trace_capture'])
    }
  };
  const service = createApple2SimRuntimeService({
    state,
    runtime,
    APPLE2_RAM_BYTES: 64 * 1024,
    setRunningState: (value) => calls.push(['running', value]),
    setCycleState: (value) => calls.push(['cycle', value]),
    setUiCyclesPendingState: (value) => calls.push(['ui', value]),
    getApple2ProgramCounter: () => 0xB82A,
    ensureApple2Ready: () => true,
    setMemoryDumpStatus: () => {},
    refreshApple2UiState: () => {},
    log: () => {}
  });

  const info = service.performApple2ResetSequence({ releaseCycles: 4 });
  assert.equal(info.pcBefore, 0xB82A);
  assert.equal(info.pcAfter, 0xB82A);
  assert.equal(info.releaseCycles, 4);
  assert.equal(info.usedResetSignal, true);
  assert.equal(state.apple2.keyQueue.length, 0);
  assert.deepEqual(
    calls.map((entry) => entry[0]),
    ['running', 'poke', 'cycles', 'poke', 'cycles', 'cycle', 'ui', 'trace_capture']
  );
});

test('apple2 sim runtime service trims RAM load to address window', async () => {
  let status = '';
  const loaded = [];
  const service = createApple2SimRuntimeService({
    state: { apple2: { keyQueue: [] } },
    runtime: {
      sim: {
        memory_load: (bytes, offset) => {
          loaded.push({ bytes: new Uint8Array(bytes), offset });
          return true;
        },
        has_signal: () => false,
        reset: () => {},
        trace_enabled: () => false
      }
    },
    APPLE2_RAM_BYTES: 8,
    setRunningState: () => {},
    setCycleState: () => {},
    setUiCyclesPendingState: () => {},
    getApple2ProgramCounter: () => 0,
    ensureApple2Ready: () => true,
    setMemoryDumpStatus: (message) => {
      status = message;
    },
    refreshApple2UiState: () => {},
    log: () => {}
  });

  const ok = await service.loadApple2MemoryDumpBytes(new Uint8Array([1, 2, 3, 4, 5, 6]), 4, {
    label: 'test'
  });
  assert.equal(ok, true);
  assert.equal(loaded.length, 1);
  assert.equal(loaded[0].offset, 4);
  assert.deepEqual(Array.from(loaded[0].bytes), [1, 2, 3, 4]);
  assert.match(status, /trimmed to 4 bytes/);
});
