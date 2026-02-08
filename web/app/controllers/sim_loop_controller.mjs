function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimLoopController requires function: ${name}`);
  }
}

export function createSimLoopController({
  dom,
  state,
  runtime,
  isApple2UiEnabled,
  refreshStatus,
  updateApple2SpeakerAudio,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  selectedClock,
  checkBreakpoints,
  formatValue,
  log,
  drainTrace,
  refreshWatchTable,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  isComponentTabActive,
  refreshActiveComponentTab,
  requestFrame = globalThis.requestAnimationFrame
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createSimLoopController requires dom/state/runtime');
  }
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('refreshStatus', refreshStatus);
  requireFn('updateApple2SpeakerAudio', updateApple2SpeakerAudio);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setRunningState', setRunningState);
  requireFn('selectedClock', selectedClock);
  requireFn('checkBreakpoints', checkBreakpoints);
  requireFn('formatValue', formatValue);
  requireFn('log', log);
  requireFn('drainTrace', drainTrace);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('isComponentTabActive', isComponentTabActive);
  requireFn('refreshActiveComponentTab', refreshActiveComponentTab);
  requireFn('requestFrame', requestFrame);

  function queueApple2Key(value) {
    if (!isApple2UiEnabled()) {
      return;
    }
    if (value == null) {
      return;
    }

    let ascii = typeof value === 'number' ? value : String(value).charCodeAt(0);
    if (!Number.isFinite(ascii)) {
      return;
    }

    if (ascii >= 97 && ascii <= 122) {
      ascii -= 32;
    }
    if (ascii === 10) {
      ascii = 0x0d;
    }
    if (ascii === 127) {
      ascii = 0x08;
    }

    state.apple2.keyQueue.push(ascii & 0xff);
    refreshStatus();
  }

  function runApple2Cycles(cycles) {
    if (!runtime.sim || !isApple2UiEnabled()) {
      return;
    }

    const key = state.apple2.keyQueue[0];
    const keyReady = state.apple2.keyQueue.length > 0;
    const result = runtime.sim.apple2_run_cpu_cycles(cycles, key || 0, keyReady);
    if (!result) {
      return;
    }

    if (result.key_cleared && state.apple2.keyQueue.length > 0) {
      state.apple2.keyQueue.shift();
    }

    state.apple2.lastCpuResult = result;
    state.apple2.lastSpeakerToggles = result.speaker_toggles;
    state.cycle += result.cycles_run;
    updateApple2SpeakerAudio(result.speaker_toggles, result.cycles_run);

    if (runtime.sim.trace_enabled()) {
      runtime.sim.trace_capture();
    }
  }

  function stepSimulation() {
    if (!runtime.sim) {
      return;
    }

    const ticks = Math.max(1, Number.parseInt(dom.stepTicks.value, 10) || 1);

    try {
      if (isApple2UiEnabled()) {
        runApple2Cycles(ticks);
      } else {
        const clk = selectedClock();
        if (clk) {
          runtime.sim.run_clock_ticks(clk, ticks);
        } else {
          runtime.sim.run_ticks(ticks);
        }
        setCycleState(state.cycle + ticks);
      }
    } catch (err) {
      log(`Step error: ${err.message || err}`);
      setRunningState(false);
    }

    drainTrace();
    refreshWatchTable();
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    if (isComponentTabActive()) {
      refreshActiveComponentTab();
    }
    setUiCyclesPendingState(0);
    refreshStatus();
  }

  function runFrame() {
    if (!state.running || !runtime.sim) {
      refreshStatus();
      return;
    }

    const batch = Math.max(1, Number.parseInt(dom.runBatch.value, 10) || 20000);
    const uiEvery = Math.max(1, Number.parseInt(dom.uiUpdateCycles?.value, 10) || batch);
    let hit = null;
    let cyclesRan = 0;

    try {
      if (isApple2UiEnabled()) {
        const before = state.cycle;
        runApple2Cycles(batch);
        cyclesRan = Math.max(0, state.cycle - before);
      } else {
        const clk = selectedClock();
        for (let i = 0; i < batch; i += 1) {
          if (clk) {
            runtime.sim.run_clock_ticks(clk, 1);
          } else {
            runtime.sim.run_ticks(1);
          }
          setCycleState(state.cycle + 1);
          cyclesRan += 1;

          hit = checkBreakpoints();
          if (hit) {
            break;
          }
        }
      }

      if (hit) {
        setRunningState(false);
        log(`Breakpoint hit at cycle ${state.cycle}: ${hit.signal}=${formatValue(hit.value, 64)}`);
      }
    } catch (err) {
      setRunningState(false);
      log(`Run error: ${err.message || err}`);
    }

    setUiCyclesPendingState(Math.max(0, state.uiCyclesPending + cyclesRan));
    const shouldRefreshUi = !state.running
      || !!hit
      || state.uiCyclesPending >= uiEvery
      || state.activeTab === 'memoryTab'
      || isComponentTabActive();

    if (shouldRefreshUi) {
      drainTrace();
      refreshWatchTable();
      refreshApple2Screen();
      refreshApple2Debug();
      if (state.activeTab === 'memoryTab') {
        refreshMemoryView();
      }
      if (isComponentTabActive()) {
        refreshActiveComponentTab();
      }
      setUiCyclesPendingState(0);
    }

    refreshStatus();
    if (state.running) {
      requestFrame(runFrame);
    }
  }

  return {
    queueApple2Key,
    runApple2Cycles,
    stepSimulation,
    runFrame
  };
}
