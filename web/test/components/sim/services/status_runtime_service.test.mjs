import test from 'node:test';
import assert from 'node:assert/strict';
import { createSimStatusRuntimeService } from '../../../../app/components/sim/services/status_runtime_service.mjs';

function createService(overrides = {}) {
  const state = {
    backend: 'compiler',
    cycle: 123,
    running: false,
    apple2: { keyQueue: [1, 2] }
  };
  const runtime = { sim: null, irMeta: null };
  return createSimStatusRuntimeService({
    state,
    runtime,
    getBackendDef: () => ({ id: 'compiler', label: 'Compiler (AOT)' }),
    currentRunnerPreset: () => ({ id: 'generic', label: 'Generic' }),
    isApple2UiEnabled: () => true,
    ...overrides
  });
}

test('sim status runtime service selectedClock and maskForWidth helpers', () => {
  const service = createService();
  assert.equal(service.selectedClock('__none__'), null);
  assert.equal(service.selectedClock('clk'), 'clk');
  assert.equal(service.maskForWidth(8), 255n);
  assert.equal(service.maskForWidth(80), (1n << 64n) - 1n);
});

test('sim status runtime service describes no-sim status', () => {
  const service = createService();
  const snapshot = service.describeStatus('__none__');
  assert.equal(snapshot.simStatus, 'Simulator not initialized');
  assert.equal(snapshot.traceStatus, 'Trace disabled');
  assert.equal(snapshot.syncReason, 'refreshStatus:no-sim');
});

test('sim status runtime service describes runtime status and clock options', () => {
  const runtime = {
    sim: {
      signal_count: () => 7,
      reg_count: () => 3,
      clock_mode: (name) => (name === 'clk_14m' ? 'forced' : 'auto'),
      trace_enabled: () => true,
      trace_change_count: () => 99,
      runner_kind: () => 'apple2',
      features: {
        hasSignalIndex: false,
        hasLiveTrace: false
      }
    },
    irMeta: {
      clockCandidates: ['clk_14m', 'clk']
    }
  };
  const service = createService({
    runtime,
    currentRunnerPreset: () => ({ id: 'apple2', label: 'Apple ][ Runner' })
  });
  const status = service.describeStatus('clk_14m');
  assert.match(status.simStatus, /Cycle 123 \| 7 signals \| 3 regs/);
  assert.match(status.traceStatus, /Trace enabled \| changes 99/);
  assert.match(status.backendStatus, /name-mode/);
  assert.match(status.runnerStatus, /apple2 mode/);
  assert.equal(status.updateIoToggles, true);

  const options = service.listClockOptions('__none__');
  assert.equal(options.options.length, 3);
  assert.equal(options.selected, 'clk_14m');
});
