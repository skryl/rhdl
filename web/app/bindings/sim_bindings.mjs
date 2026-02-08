import { createListenerGroup } from './listener_bindings.mjs';

export function bindSimBindings({ dom, state, runtime, actions }) {
  const listeners = createListenerGroup();
  const scheduleAnimationFrame = typeof actions.scheduleAnimationFrame === 'function'
    ? actions.scheduleAnimationFrame
    : ((cb) => requestAnimationFrame(cb));

  listeners.on(dom.initBtn, 'click', () => {
    actions.initializeSimulator();
  });

  listeners.on(dom.resetBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    if (actions.isApple2UiEnabled()) {
      actions.performApple2ResetSequence();
    } else {
      actions.setRunningState(false);
      actions.setCycleState(0);
      actions.setUiCyclesPendingState(0);
      runtime.sim.reset();
    }
    actions.initializeTrace();
    actions.refreshWatchTable();
    actions.refreshApple2Screen();
    actions.refreshApple2Debug();
    actions.refreshMemoryView();
    if (actions.isComponentTabActive()) {
      actions.refreshActiveComponentTab();
    }
    actions.updateApple2SpeakerAudio(0, 0);
    actions.refreshStatus();
    actions.log('Simulator reset');
  });

  listeners.on(dom.stepBtn, 'click', () => {
    actions.stepSimulation();
  });

  listeners.on(dom.runBtn, 'click', () => {
    if (!runtime.sim || state.running) {
      return;
    }
    actions.setRunningState(true);
    actions.refreshStatus();
    scheduleAnimationFrame(actions.runFrame);
  });

  listeners.on(dom.pauseBtn, 'click', () => {
    actions.setRunningState(false);
    actions.updateApple2SpeakerAudio(0, 0);
    actions.drainTrace();
    actions.refreshWatchTable();
    actions.refreshApple2Screen();
    actions.refreshApple2Debug();
    if (state.activeTab === 'memoryTab') {
      actions.refreshMemoryView();
    } else if (actions.isComponentTabActive()) {
      actions.refreshActiveComponentTab();
    }
    actions.setUiCyclesPendingState(0);
    actions.refreshStatus();
    actions.log('Simulation paused');
  });

  listeners.on(dom.traceStartBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    runtime.sim.trace_start();
    runtime.sim.trace_capture();
    actions.drainTrace();
    actions.refreshStatus();
  });

  listeners.on(dom.traceStopBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    runtime.sim.trace_stop();
    actions.refreshStatus();
  });

  listeners.on(dom.traceClearBtn, 'click', () => {
    if (!runtime.sim) {
      return;
    }
    runtime.sim.trace_clear();
    runtime.parser.reset();
    actions.refreshStatus();
    actions.log('Trace cleared');
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
    actions.log('Saved VCD file');
  });

  listeners.on(dom.addWatchBtn, 'click', () => {
    const signal = String(dom.watchSignal?.value || '').trim();
    if (!signal) {
      return;
    }
    actions.addWatchSignal(signal);
    dom.watchSignal.value = '';
  });

  listeners.on(dom.watchList, 'watch-remove', (event) => {
    const name = event?.detail?.name;
    if (!name) {
      return;
    }
    actions.removeWatchSignal(name);
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

    const parsed = actions.parseNumeric(valueRaw);
    if (parsed == null) {
      actions.log('Invalid breakpoint value');
      return;
    }

    let idx = null;
    if (runtime.sim.features.hasSignalIndex) {
      const resolved = runtime.sim.get_signal_idx(signal);
      if (resolved < 0) {
        actions.log(`Unknown signal for breakpoint: ${signal}`);
        return;
      }
      idx = resolved;
    } else if (!runtime.sim.has_signal(signal)) {
      actions.log(`Unknown signal for breakpoint: ${signal}`);
      return;
    }

    const width = actions.getSignalWidth(signal);
    const mask = actions.maskForWidth(width);
    const value = parsed & mask;

    actions.breakpointAddOrReplace({ name: signal, idx, width, value });
    actions.renderBreakpointList();
    actions.log(`Breakpoint added: ${signal}=${valueRaw}`);

    dom.bpSignal.value = '';
    dom.bpValue.value = '';
  });

  listeners.on(dom.clearBpBtn, 'click', () => {
    actions.breakpointClear();
    actions.renderBreakpointList();
    actions.log('Breakpoints cleared');
  });

  listeners.on(dom.bpList, 'breakpoint-remove', (event) => {
    const name = event?.detail?.name;
    if (!name) {
      return;
    }
    actions.breakpointRemove(name);
    actions.renderBreakpointList();
  });

  return () => {
    listeners.dispose();
  };
}
