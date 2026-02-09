import test from 'node:test';
import assert from 'node:assert/strict';

import { bindSimBindings } from '../../../../app/components/sim/bindings/bindings.mjs';

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
  const runFrame = () => {};

  const teardown = bindSimBindings({
    dom,
    state,
    runtime,
    scheduleAnimationFrame: (cb) => calls.push(['raf', cb]),
    sim: {
      initializeSimulator: () => {},
      initializeTrace: () => {},
      refreshStatus: () => calls.push(['refreshStatus']),
      step: () => {},
      runFrame,
      drainTrace: () => {}
    },
    apple2: {
      isUiEnabled: () => false,
      performResetSequence: () => {},
      refreshScreen: () => {},
      refreshDebug: () => {},
      refreshMemoryView: () => {},
      updateSpeakerAudio: () => {}
    },
    components: {
      isTabActive: () => false,
      refreshActiveTab: () => {}
    },
    watch: {
      refreshTable: () => {},
      addSignal: () => {},
      removeSignal: () => {},
      addBreakpoint: () => {},
      clearBreakpoints: () => {},
      removeBreakpoint: () => {}
    },
    store: {
      setRunningState: (value) => {
      state.running = value;
      calls.push(['setRunningState', value]);
    },
      setCycleState: () => {},
      setUiCyclesPendingState: () => {}
    },
    log: () => {}
  });

  dom.runBtn.dispatchEvent(new Event('click'));
  assert.deepEqual(calls, [
    ['setRunningState', true],
    ['refreshStatus'],
    ['raf', runFrame]
  ]);

  calls.length = 0;
  teardown();
  state.running = false;
  dom.runBtn.dispatchEvent(new Event('click'));
  assert.deepEqual(calls, []);
});
