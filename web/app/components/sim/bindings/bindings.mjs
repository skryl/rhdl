import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';

export function bindSimBindings({
  dom,
  state,
  runtime,
  sim,
  apple2,
  components,
  watch,
  store,
  log,
  scheduleAnimationFrame
}) {
  const listeners = createListenerGroup();
  const scheduleFrame = typeof scheduleAnimationFrame === 'function'
    ? scheduleAnimationFrame
    : ((cb) => requestAnimationFrame(cb));

  listeners.on(dom.initBtn, 'click', () => {
    sim.initializeSimulator();
  });

  listeners.on(dom.resetBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    if (apple2.isUiEnabled()) {
      apple2.performResetSequence();
    } else {
      store.setRunningState(false);
      store.setCycleState(0);
      store.setUiCyclesPendingState(0);
      runtime.sim.reset();
    }
    sim.initializeTrace();
    watch.refreshTable();
    apple2.refreshScreen();
    apple2.refreshDebug();
    apple2.refreshMemoryView();
    if (components.isTabActive()) {
      components.refreshActiveTab();
    }
    apple2.updateSpeakerAudio(0, 0);
    sim.refreshStatus();
    log('Simulator reset');
  });

  listeners.on(dom.stepBtn, 'click', () => {
    sim.step();
  });

  listeners.on(dom.runBtn, 'click', () => {
    if (!runtime.sim || state.running) {
      return;
    }
    if (typeof sim.resetThroughputSampling === 'function') {
      sim.resetThroughputSampling();
    }
    store.setRunningState(true);
    sim.refreshStatus();
    scheduleFrame(sim.runFrame);
  });

  listeners.on(dom.pauseBtn, 'click', () => {
    store.setRunningState(false);
    apple2.updateSpeakerAudio(0, 0);
    sim.drainTrace();
    watch.refreshTable();
    apple2.refreshScreen();
    apple2.refreshDebug();
    if (state.activeTab === 'memoryTab') {
      apple2.refreshMemoryView();
    } else if (components.isTabActive()) {
      components.refreshActiveTab();
    }
    store.setUiCyclesPendingState(0);
    sim.refreshStatus();
    log('Simulation paused');
  });

  listeners.on(dom.traceStartBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    runtime.sim.trace_start();
    runtime.sim.trace_capture();
    sim.drainTrace();
    sim.refreshStatus();
  });

  listeners.on(dom.traceStopBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    runtime.sim.trace_stop();
    sim.refreshStatus();
  });

  listeners.on(dom.traceClearBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    runtime.sim.trace_clear();
    runtime.parser.reset();
    sim.refreshStatus();
    log('Trace cleared');
  });

  listeners.on(dom.downloadVcdBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    const vcd = runtime.sim.trace_to_vcd();
    const blob = new Blob([vcd], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'rhdl_trace.vcd';
    a.click();
    URL.revokeObjectURL(url);
    log('Saved VCD file');
  });

  listeners.on(dom.addWatchBtn, 'click', () => {
    const signal = String(dom.watchSignal?.value || '').trim();
    if (!signal) {
      return;
    }
    watch.addSignal(signal);
    dom.watchSignal.value = '';
  });

  listeners.on(dom.watchList, 'watch-remove', (event) => {
    const name = event?.detail?.name;
    if (!name) {
      return;
    }
    watch.removeSignal(name);
  });

  listeners.on(dom.addBpBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }

    const signal = String(dom.bpSignal?.value || '').trim();
    const valueRaw = String(dom.bpValue?.value || '').trim();
    if (!signal || !valueRaw) {
      return;
    }

    try {
      watch.addBreakpoint(signal, valueRaw);
      log(`Breakpoint added: ${signal}=${valueRaw}`);
      dom.bpSignal.value = '';
      dom.bpValue.value = '';
    } catch (err) {
      log(err?.message || String(err));
    }
  });

  listeners.on(dom.clearBpBtn, 'click', () => {
    watch.clearBreakpoints();
    log('Breakpoints cleared');
  });

  listeners.on(dom.bpList, 'breakpoint-remove', (event) => {
    const name = event?.detail?.name;
    if (!name) {
      return;
    }
    watch.removeBreakpoint(name);
  });

  return () => {
    listeners.dispose();
  };
}
