import test from 'node:test';
import assert from 'node:assert/strict';

import { createSimLoopController } from '../../../../app/components/sim/controllers/loop_controller';

function createHarness() {
  const calls: any[] = [];
  const dom = {
    stepTicks: { value: '1' },
    runBatch: { value: '10' },
    uiUpdateCycles: { value: '10' }
  };
  const state = {
    running: false,
    cycle: 0,
    uiCyclesPending: 0,
    activeTab: 'vcdTab',
    apple2: {
      keyQueue: [],
      lastCpuResult: null,
      lastSpeakerToggles: 0
    }
  };
  const runtime = {
    sim: null
  };
  const controller = createSimLoopController({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    refreshStatus: () => calls.push('refreshStatus'),
    updateApple2SpeakerAudio: () => calls.push('updateApple2SpeakerAudio'),
    setCycleState: (v: any) => {
      state.cycle = v;
      calls.push(`setCycle:${v}`);
    },
    setUiCyclesPendingState: (v: any) => {
      state.uiCyclesPending = v;
      calls.push(`setPending:${v}`);
    },
    setRunningState: (v: any) => {
      state.running = v;
      calls.push(`setRunning:${v}`);
    },
    selectedClock: () => null,
    checkBreakpoints: () => null,
    formatValue: (value: any) => String(value),
    log: (message: any) => calls.push(`log:${message}`),
    drainTrace: () => calls.push('drainTrace'),
    refreshWatchTable: () => calls.push('refreshWatchTable'),
    refreshApple2Screen: () => calls.push('refreshApple2Screen'),
    refreshApple2Debug: () => calls.push('refreshApple2Debug'),
    refreshMemoryView: () => calls.push('refreshMemoryView'),
    isComponentTabActive: () => false,
    refreshActiveComponentTab: () => calls.push('refreshActiveComponentTab'),
    requestFrame: () => calls.push('requestFrame')
  });
  return { controller, state, runtime, calls };
}

test('queueApple2Key normalizes lowercase chars and enter/backspace', () => {
  const { controller, state } = createHarness();
  controller.queueApple2Key('a');
  controller.queueApple2Key('\n');
  controller.queueApple2Key(String.fromCharCode(127));
  assert.deepEqual(state.apple2.keyQueue, [65, 13, 8]);
});

test('runApple2Cycles advances cycle and captures trace when enabled', () => {
  const { controller, state, runtime } = createHarness();
  runtime.sim = {
    runner_run_cycles: () => ({ key_cleared: false, speaker_toggles: 3, cycles_run: 5 }),
    trace_enabled: () => true,
    trace_capture: () => {}
  } as any;
  controller.runApple2Cycles(5);
  assert.equal(state.cycle, 5);
  assert.equal(state.apple2.lastSpeakerToggles, 3);
});

test('stepSimulation no-ops safely without simulator', () => {
  const { controller, calls } = createHarness();
  controller.stepSimulation();
  assert.deepEqual(calls, []);
});

test('runFrame refreshes status when not running', () => {
  const { controller, calls } = createHarness();
  controller.runFrame();
  assert.equal(calls.includes('refreshStatus'), true);
});
