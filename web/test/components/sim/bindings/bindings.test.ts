import test from 'node:test';
import assert from 'node:assert/strict';

import { bindSimBindings } from '../../../../app/components/sim/bindings/bindings';

function makeTarget(extra: any = {}) {
  return Object.assign(new EventTarget(), extra);
}

test('bindSimBindings starts run loop and supports teardown', () => {
  const calls: any[] = [];
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
    scheduleAnimationFrame: (cb: any) => calls.push(['raf', cb]),
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
      setRunningState: (value: any) => {
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

test('bindSimBindings preserves current trace enabled state across reset', () => {
  const calls: any[] = [];
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
  const runtime = {
    sim: {
      trace_enabled: () => true,
      reset: () => calls.push(['sim.reset'])
    },
    parser: { reset: () => {} }
  };

  const teardown = bindSimBindings({
    dom,
    state: { running: false, activeTab: 'ioTab' },
    runtime,
    sim: {
      initializeSimulator: () => {},
      initializeTrace: (options: any) => calls.push(['initializeTrace', options]),
      refreshStatus: () => {},
      step: () => {},
      runFrame: () => {},
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
      setRunningState: () => {},
      setCycleState: () => {},
      setUiCyclesPendingState: () => {}
    },
    log: () => {}
  });

  dom.resetBtn.dispatchEvent(new Event('click'));
  teardown();

  assert.deepEqual(calls, [
    ['sim.reset'],
    ['initializeTrace', { enabled: true }]
  ]);
});
