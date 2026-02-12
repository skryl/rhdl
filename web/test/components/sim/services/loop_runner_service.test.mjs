import test from 'node:test';
import assert from 'node:assert/strict';

import { createSimLoopRunnerService } from '../../../../app/components/sim/services/loop_runner_service.mjs';

function createHarness({ runBatch = '10', uiUpdateCycles = '10', nowSequence = null } = {}) {
  const calls = [];
  const runCalls = [];
  const dom = {
    stepTicks: { value: '1' },
    runBatch: { value: String(runBatch) },
    uiUpdateCycles: { value: String(uiUpdateCycles) }
  };
  const state = {
    running: true,
    cycle: 0,
    uiCyclesPending: 0,
    activeTab: 'ioTab',
    apple2: {
      keyQueue: [],
      lastCpuResult: null,
      lastSpeakerToggles: 0,
      ioConfig: {}
    }
  };
  const runtime = {
    sim: {
      runner_run_cycles: (cycles) => {
        runCalls.push(cycles);
        return {
          key_cleared: false,
          speaker_toggles: 0,
          cycles_run: cycles
        };
      },
      trace_enabled: () => false
    },
    throughput: {
      cyclesPerSecond: 0,
      lastSampleTimeMs: null,
      lastSampleCycle: 0
    }
  };

  const nowValues = Array.isArray(nowSequence) ? nowSequence.slice() : null;
  const nowMs = () => {
    if (!nowValues || nowValues.length === 0) {
      return Date.now();
    }
    if (nowValues.length === 1) {
      return nowValues[0];
    }
    return nowValues.shift();
  };

  const controller = createSimLoopRunnerService({
    dom,
    state,
    runtime,
    isApple2UiEnabled: () => true,
    refreshStatus: () => calls.push('refreshStatus'),
    updateApple2SpeakerAudio: () => calls.push('updateApple2SpeakerAudio'),
    setCycleState: (v) => {
      state.cycle = v;
      calls.push(`setCycle:${v}`);
    },
    setUiCyclesPendingState: (v) => {
      state.uiCyclesPending = v;
      calls.push(`setPending:${v}`);
    },
    setRunningState: (v) => {
      state.running = v;
      calls.push(`setRunning:${v}`);
    },
    selectedClock: () => null,
    checkBreakpoints: () => null,
    formatValue: (value) => String(value),
    log: (message) => calls.push(`log:${message}`),
    drainTrace: () => calls.push('drainTrace'),
    refreshWatchTable: () => calls.push('refreshWatchTable'),
    refreshApple2Screen: () => calls.push('refreshApple2Screen'),
    refreshApple2Debug: () => calls.push('refreshApple2Debug'),
    refreshMemoryView: () => calls.push('refreshMemoryView'),
    isComponentTabActive: () => false,
    refreshActiveComponentTab: () => calls.push('refreshActiveComponentTab'),
    requestFrame: () => calls.push('requestFrame'),
    nowMs
  });

  return { controller, dom, state, runtime, calls, runCalls };
}

test('runFrame uses cycles/frame and ui every values for runner batching', () => {
  const { controller, state, calls, runCalls } = createHarness({
    runBatch: '7',
    uiUpdateCycles: '14'
  });

  controller.runFrame();
  assert.deepEqual(runCalls, [7]);
  assert.equal(state.cycle, 7);
  assert.equal(state.uiCyclesPending, 7);
  assert.equal(calls.includes('refreshWatchTable'), false);
  assert.equal(calls.includes('refreshApple2Screen'), false);

  controller.runFrame();
  assert.deepEqual(runCalls, [7, 7]);
  assert.equal(state.cycle, 14);
  assert.equal(state.uiCyclesPending, 0);
  assert.equal(calls.includes('refreshWatchTable'), true);
  assert.equal(calls.includes('refreshApple2Screen'), true);
  assert.equal(calls.includes('refreshApple2Debug'), true);
});

test('runFrame re-reads cycles/frame from DOM each frame', () => {
  const { controller, dom, runCalls } = createHarness({
    runBatch: '5',
    uiUpdateCycles: '1000'
  });

  controller.runFrame();
  dom.runBatch.value = '9';
  controller.runFrame();

  assert.deepEqual(runCalls, [5, 9]);
});

test('runFrame updates cycles-per-second sampling', () => {
  const { controller, runtime } = createHarness({
    runBatch: '20',
    uiUpdateCycles: '1000',
    nowSequence: [0, 100]
  });

  controller.resetThroughputSampling();
  controller.runFrame();

  assert.equal(Math.round(runtime.throughput.cyclesPerSecond), 200);
});
