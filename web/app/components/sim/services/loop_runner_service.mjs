import {
  normalizeApple2KeyCode,
  normalizeMappedKeyCode,
  parseStepTickCount,
  parseRunLoopConfig,
  executeGenericRunBatch,
  shouldRefreshUiAfterRun
} from './loop_runtime_service.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimLoopRunnerService requires function: ${name}`);
  }
}

export function createSimLoopRunnerService({
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
    throw new Error('createSimLoopRunnerService requires dom/state/runtime');
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

  function currentIoConfig() {
    return state.apple2?.ioConfig || {};
  }

  function readMappedSoundByte() {
    const soundCfg = currentIoConfig().sound || {};
    if (!soundCfg.enabled || soundCfg.mode !== 'memory_mapped') {
      return null;
    }
    const addr = Number.parseInt(soundCfg.addr, 10);
    if (!Number.isFinite(addr) || addr < 0) {
      return null;
    }
    if (typeof runtime.sim.memory_read_byte !== 'function') {
      return null;
    }
    return runtime.sim.memory_read_byte(addr & 0xFFFF, { mapped: true }) & 0xFF;
  }

  function pollMappedSound(cyclesRun) {
    const soundCfg = currentIoConfig().sound || {};
    if (!soundCfg.enabled || soundCfg.mode !== 'memory_mapped') {
      state.apple2.lastMappedSoundValue = null;
      return;
    }
    const current = readMappedSoundByte();
    if (current == null) {
      return;
    }

    const mask = Number.parseInt(soundCfg.mask, 10);
    const bitMask = Number.isFinite(mask) ? (mask & 0xFF) : 0x01;
    const previous = Number.parseInt(state.apple2.lastMappedSoundValue, 10);
    state.apple2.lastMappedSoundValue = current;
    if (!Number.isFinite(previous)) {
      return;
    }

    const toggledBits = (previous ^ current) & bitMask;
    if (!toggledBits) {
      return;
    }
    const toggles = toggledBits.toString(2).split('1').length - 1;
    state.apple2.lastSpeakerToggles = (state.apple2.lastSpeakerToggles || 0) + toggles;
    updateApple2SpeakerAudio(toggles, Math.max(1, cyclesRun));
  }

  function runGenericCycles(cycles) {
    const ticks = Math.max(0, Number.parseInt(cycles, 10) || 0);
    const clk = selectedClock();
    if (clk) {
      runtime.sim.run_clock_ticks(clk, ticks);
    } else {
      runtime.sim.run_ticks(ticks);
    }
    state.cycle += ticks;
    pollMappedSound(ticks);
    if (runtime.sim.trace_enabled()) {
      runtime.sim.trace_capture();
    }
  }

  function queueApple2Key(value) {
    if (!isApple2UiEnabled()) {
      return;
    }

    const ioConfig = currentIoConfig();
    const keyboardCfg = ioConfig.keyboard || {};
    if (keyboardCfg.enabled === false) {
      return;
    }
    const normalized = keyboardCfg.mode === 'memory_mapped'
      ? normalizeMappedKeyCode(value, keyboardCfg)
      : normalizeApple2KeyCode(value);
    if (normalized == null) {
      return;
    }

    if (keyboardCfg.mode === 'memory_mapped' && typeof runtime.sim?.memory_write_byte === 'function') {
      const dataAddr = Number.parseInt(keyboardCfg.dataAddr, 10);
      if (Number.isFinite(dataAddr) && dataAddr >= 0) {
        runtime.sim.memory_write_byte(dataAddr & 0xFFFF, normalized, { mapped: true });
      }

      const strobeAddr = Number.parseInt(keyboardCfg.strobeAddr, 10);
      if (Number.isFinite(strobeAddr) && strobeAddr >= 0) {
        const strobeValue = Number.parseInt(keyboardCfg.strobeValue, 10);
        runtime.sim.memory_write_byte(strobeAddr & 0xFFFF, Number.isFinite(strobeValue) ? (strobeValue & 0xFF) : 1, { mapped: true });
        const clearValue = Number.parseInt(keyboardCfg.strobeClearValue, 10);
        if (Number.isFinite(clearValue)) {
          runtime.sim.memory_write_byte(strobeAddr & 0xFFFF, clearValue & 0xFF, { mapped: true });
        }
      }
      refreshStatus();
      return;
    }

    state.apple2.keyQueue.push(normalized);
    refreshStatus();
  }

  function runApple2Cycles(cycles) {
    if (!runtime.sim || !isApple2UiEnabled()) {
      return;
    }

    if (typeof runtime.sim.runner_run_cycles !== 'function') {
      runGenericCycles(cycles);
      return;
    }

    const key = state.apple2.keyQueue[0];
    const keyReady = state.apple2.keyQueue.length > 0;
    const result = runtime.sim.runner_run_cycles(cycles, key || 0, keyReady);
    if (!result) {
      runGenericCycles(cycles);
      return;
    }

    if (result.key_cleared && state.apple2.keyQueue.length > 0) {
      state.apple2.keyQueue.shift();
    }

    const cyclesRun = Math.max(0, Number.parseInt(result.cycles_run, 10) || 0);
    const speakerToggles = Math.max(0, Number.parseInt(result.speaker_toggles, 10) || 0);
    state.apple2.lastCpuResult = result;
    state.apple2.lastSpeakerToggles = speakerToggles;
    state.cycle += cyclesRun;
    if (speakerToggles > 0) {
      updateApple2SpeakerAudio(speakerToggles, Math.max(1, cyclesRun));
    }
    pollMappedSound(cyclesRun);
    if (runtime.sim.trace_enabled()) {
      runtime.sim.trace_capture();
    }
  }

  function stepSimulation() {
    if (!runtime.sim) {
      return;
    }

    const ticks = parseStepTickCount(dom.stepTicks?.value);

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

    const { batch, uiEvery } = parseRunLoopConfig({
      runBatchRaw: dom.runBatch?.value,
      uiUpdateCyclesRaw: dom.uiUpdateCycles?.value
    });
    let hit = null;
    let cyclesRan = 0;

    try {
      if (isApple2UiEnabled()) {
        const before = state.cycle;
        runApple2Cycles(batch);
        cyclesRan = Math.max(0, state.cycle - before);
      } else {
        const genericRunResult = executeGenericRunBatch({
          runtime,
          state,
          batch,
          selectedClock,
          setCycleState,
          checkBreakpoints
        });
        cyclesRan = genericRunResult.cyclesRan;
        hit = genericRunResult.hit;
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
    const shouldRefreshUi = shouldRefreshUiAfterRun({
      state,
      hit,
      uiEvery,
      isComponentTabActive
    });

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
