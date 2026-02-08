import test from 'node:test';
import assert from 'node:assert/strict';

import { createSimStatusController } from '../../app/controllers/sim_status_controller.mjs';

function createHarness() {
  const scheduleCalls = [];
  const ioCalls = [];
  const dom = {
    clockSignal: { value: '__none__' },
    simStatus: { textContent: '' },
    traceStatus: { textContent: '' },
    backendStatus: { textContent: '' },
    runnerStatus: { textContent: '' },
    apple2KeyStatus: { textContent: '' }
  };
  const state = {
    backend: 'compiler',
    cycle: 123,
    running: false,
    apple2: { keyQueue: [1, 2] }
  };
  const runtime = {
    sim: null,
    irMeta: null
  };
  const controller = createSimStatusController({
    dom,
    state,
    runtime,
    getBackendDef: () => ({ id: 'compiler', label: 'Compiler (AOT)' }),
    currentRunnerPreset: () => ({ id: 'generic', label: 'Generic' }),
    isApple2UiEnabled: () => true,
    updateIoToggleUi: () => ioCalls.push('io'),
    scheduleReduxUxSync: (reason) => scheduleCalls.push(reason),
    litRender: () => {},
    html: (strings, ...values) => ({ strings, values })
  });
  return { controller, dom, state, runtime, scheduleCalls, ioCalls };
}

test('selectedClock returns null for none marker', () => {
  const { controller, dom } = createHarness();
  dom.clockSignal.value = '__none__';
  assert.equal(controller.selectedClock(), null);
  dom.clockSignal.value = 'clk';
  assert.equal(controller.selectedClock(), 'clk');
});

test('maskForWidth clamps to 64-bit and handles narrow widths', () => {
  const { controller } = createHarness();
  assert.equal(controller.maskForWidth(1), 1n);
  assert.equal(controller.maskForWidth(8), 255n);
  assert.equal(controller.maskForWidth(80), (1n << 64n) - 1n);
});

test('refreshStatus without simulator writes not-initialized labels', () => {
  const { controller, dom, scheduleCalls } = createHarness();
  controller.refreshStatus();
  assert.equal(dom.simStatus.textContent, 'Simulator not initialized');
  assert.equal(dom.traceStatus.textContent, 'Trace disabled');
  assert.match(dom.backendStatus.textContent, /Backend: compiler/);
  assert.equal(scheduleCalls.includes('refreshStatus:no-sim'), true);
});

test('refreshStatus with simulator writes running metrics and queues sync', () => {
  const { controller, dom, runtime, scheduleCalls, ioCalls } = createHarness();
  dom.clockSignal.value = 'clk';
  runtime.sim = {
    signal_count: () => 7,
    reg_count: () => 3,
    clock_mode: () => 'forced',
    trace_enabled: () => true,
    trace_change_count: () => 99,
    apple2_mode: () => true,
    features: {
      hasSignalIndex: false,
      hasLiveTrace: false
    }
  };
  controller.refreshStatus();
  assert.match(dom.simStatus.textContent, /Cycle 123 \| 7 signals \| 3 regs/);
  assert.match(dom.traceStatus.textContent, /Trace enabled \| changes 99/);
  assert.match(dom.backendStatus.textContent, /name-mode/);
  assert.match(dom.backendStatus.textContent, /vcd-snapshot/);
  assert.match(dom.runnerStatus.textContent, /Generic \| apple2 mode/);
  assert.match(dom.apple2KeyStatus.textContent, /Keyboard queue: 2/);
  assert.equal(ioCalls.length, 1);
  assert.equal(scheduleCalls.includes('refreshStatus'), true);
});
