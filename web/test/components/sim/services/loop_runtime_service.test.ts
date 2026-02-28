import test from 'node:test';
import assert from 'node:assert/strict';

import {
  normalizeApple2KeyCode,
  normalizeUartKeyCode,
  parseStepTickCount,
  parseRunLoopConfig,
  executeGenericRunBatch,
  shouldRefreshUiAfterRun
} from '../../../../app/components/sim/services/loop_runtime_service';

test('normalizeApple2KeyCode normalizes lowercase and control keys', () => {
  assert.equal(normalizeApple2KeyCode('a'), 65);
  assert.equal(normalizeApple2KeyCode('\n'), 13);
  assert.equal(normalizeApple2KeyCode(String.fromCharCode(127)), 8);
  assert.equal(normalizeApple2KeyCode(null), null);
});

test('normalizeUartKeyCode preserves character case while normalizing controls', () => {
  assert.equal(normalizeUartKeyCode('a'), 97);
  assert.equal(normalizeUartKeyCode('A'), 65);
  assert.equal(normalizeUartKeyCode('\n'), 13);
  assert.equal(normalizeUartKeyCode(String.fromCharCode(127)), 8);
  assert.equal(normalizeUartKeyCode(null), null);
});

test('parseStepTickCount and parseRunLoopConfig clamp values', () => {
  assert.equal(parseStepTickCount('0'), 1);
  assert.equal(parseStepTickCount('12'), 12);
  assert.deepEqual(parseRunLoopConfig({ runBatchRaw: '0', uiUpdateCyclesRaw: '' }), { batch: 1, uiEvery: 1 });
  assert.deepEqual(parseRunLoopConfig({ runBatchRaw: '10', uiUpdateCyclesRaw: '20' }), { batch: 10, uiEvery: 20 });
});

test('executeGenericRunBatch advances cycles and stops on breakpoint', () => {
  const state = { cycle: 0 };
  let tickCalls = 0;
  let breakChecks = 0;
  const result = executeGenericRunBatch({
    runtime: {
      sim: {
        run_ticks: () => {
          tickCalls += 1;
        },
        run_clock_ticks: () => {}
      }
    },
    state,
    batch: 5,
    selectedClock: () => null,
    setCycleState: (value) => {
      state.cycle = value;
    },
    checkBreakpoints: () => {
      breakChecks += 1;
      return breakChecks === 3 ? { signal: 'x', value: 1n } : null;
    }
  });

  assert.equal(tickCalls, 3);
  assert.equal(state.cycle, 3);
  assert.deepEqual(result.hit, { signal: 'x', value: 1n });
  assert.equal(result.cyclesRan, 3);
});

test('shouldRefreshUiAfterRun respects run state and tabs', () => {
  assert.equal(shouldRefreshUiAfterRun({
    state: { running: false, uiCyclesPending: 0, activeTab: 'vcdTab' },
    hit: null,
    uiEvery: 10,
    isComponentTabActive: () => false
  }), true);

  assert.equal(shouldRefreshUiAfterRun({
    state: { running: true, uiCyclesPending: 2, activeTab: 'vcdTab' },
    hit: null,
    uiEvery: 10,
    isComponentTabActive: () => false
  }), false);
});

test('shouldRefreshUiAfterRun suppresses follower refresh while running when trace is disabled', () => {
  assert.equal(shouldRefreshUiAfterRun({
    state: { running: true, uiCyclesPending: 200, activeTab: 'memoryTab' },
    hit: null,
    uiEvery: 10,
    isComponentTabActive: () => true,
    traceFollowEnabled: false
  }), false);

  assert.equal(shouldRefreshUiAfterRun({
    state: { running: false, uiCyclesPending: 200, activeTab: 'memoryTab' },
    hit: null,
    uiEvery: 10,
    isComponentTabActive: () => true,
    traceFollowEnabled: false
  }), true);
});
