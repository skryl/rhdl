import test from 'node:test';
import assert from 'node:assert/strict';

import { bindSimBindings } from '../../app/bindings/sim_bindings.mjs';

function makeTarget(extra = {}) {
  return Object.assign(new EventTarget(), extra);
}

test('bindSimBindings starts run loop and supports teardown', () => {
  const calls = [];
  const dom = {
    initBtn: makeTarget(),
    resetBtn: makeTarget(),
    stepBtn: makeTarget(),
    runBtn: makeTarget(),
    pauseBtn: makeTarget(),
    traceStartBtn: makeTarget(),
    traceStopBtn: makeTarget(),
    traceClearBtn: makeTarget(),
    downloadVcdBtn: makeTarget(),
    addWatchBtn: makeTarget(),
    watchList: makeTarget(),
    addBpBtn: makeTarget(),
    clearBpBtn: makeTarget(),
    bpList: makeTarget(),
    watchSignal: { value: '' },
    bpSignal: { value: '' },
    bpValue: { value: '' }
  };

  const state = {
    running: false,
    activeTab: 'ioTab'
  };

  const runtime = {
    sim: {},
    parser: { reset: () => {} }
  };

  const actions = {
    scheduleAnimationFrame: (cb) => calls.push(['raf', cb]),
    initializeSimulator: () => {},
    isApple2UiEnabled: () => false,
    performApple2ResetSequence: () => {},
    setRunningState: (value) => {
      state.running = value;
      calls.push(['setRunningState', value]);
    },
    setCycleState: () => {},
    setUiCyclesPendingState: () => {},
    initializeTrace: () => {},
    refreshWatchTable: () => {},
    refreshApple2Screen: () => {},
    refreshApple2Debug: () => {},
    refreshMemoryView: () => {},
    isComponentTabActive: () => false,
    refreshActiveComponentTab: () => {},
    updateApple2SpeakerAudio: () => {},
    refreshStatus: () => calls.push(['refreshStatus']),
    log: () => {},
    stepSimulation: () => {},
    runFrame: () => {},
    drainTrace: () => {},
    addWatchSignal: () => {},
    removeWatchSignal: () => {},
    parseNumeric: () => null,
    maskForWidth: () => 0n,
    formatValue: () => '',
    breakpointAddOrReplace: () => {},
    breakpointClear: () => {},
    breakpointRemove: () => {},
    renderBreakpointList: () => {},
    getSignalWidth: () => 1
  };

  const teardown = bindSimBindings({ dom, state, runtime, actions });

  dom.runBtn.dispatchEvent(new Event('click'));
  assert.deepEqual(calls, [
    ['setRunningState', true],
    ['refreshStatus'],
    ['raf', actions.runFrame]
  ]);

  calls.length = 0;
  teardown();
  state.running = false;
  dom.runBtn.dispatchEvent(new Event('click'));
  assert.deepEqual(calls, []);
});
