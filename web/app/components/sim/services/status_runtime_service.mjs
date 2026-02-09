function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimStatusRuntimeService requires function: ${name}`);
  }
}

export function createSimStatusRuntimeService({
  state,
  runtime,
  getBackendDef,
  currentRunnerPreset,
  isApple2UiEnabled
} = {}) {
  if (!state || !runtime) {
    throw new Error('createSimStatusRuntimeService requires state/runtime');
  }
  requireFn('getBackendDef', getBackendDef);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);

  function selectedClock(value) {
    const val = String(value || '').trim();
    if (!val || val === '__none__') {
      return null;
    }
    return val;
  }

  function maskForWidth(width) {
    if (width >= 64) {
      return (1n << 64n) - 1n;
    }
    return (1n << BigInt(width)) - 1n;
  }

  function describeStatus(clockValue) {
    const backendDef = getBackendDef(state.backend);
    if (!runtime.sim) {
      return {
        simStatus: 'Simulator not initialized',
        traceStatus: 'Trace disabled',
        backendStatus: `Backend: ${backendDef.id}`,
        runnerStatus: 'Runner not initialized',
        apple2KeyStatus: null,
        updateIoToggles: false,
        syncReason: 'refreshStatus:no-sim'
      };
    }

    const sigs = runtime.sim.signal_count();
    const regs = runtime.sim.reg_count();
    const clk = selectedClock(clockValue);
    const mode = clk ? runtime.sim.clock_mode(clk) : null;
    const clockPart = clk ? ` | clock ${clk}${mode && mode !== 'unknown' ? ` (${mode})` : ''}` : '';
    const simStatus =
      `Cycle ${state.cycle} | ${sigs} signals | ${regs} regs` +
      `${clockPart} ${state.running ? '| RUNNING' : '| PAUSED'}`;
    const traceStatus =
      `Trace ${runtime.sim.trace_enabled() ? 'enabled' : 'disabled'}` +
      ` | changes ${runtime.sim.trace_change_count()}`;

    const notes = [];
    if (!runtime.sim.features.hasSignalIndex) {
      notes.push('name-mode');
    }
    if (!runtime.sim.features.hasLiveTrace) {
      notes.push('vcd-snapshot');
    }
    const backendStatus =
      `Backend: ${backendDef.id}${notes.length > 0 ? ` (${notes.join(', ')})` : ''}`;

    const preset = currentRunnerPreset();
    const apple2Flag = runtime.sim.apple2_mode() ? ' | apple2 mode' : '';
    const runnerStatus = `${preset.label}${apple2Flag} | ${backendDef.label}`;

    return {
      simStatus,
      traceStatus,
      backendStatus,
      runnerStatus,
      apple2KeyStatus: isApple2UiEnabled() ? `Keyboard queue: ${state.apple2.keyQueue.length}` : null,
      updateIoToggles: true,
      syncReason: 'refreshStatus'
    };
  }

  function listClockOptions(currentValue) {
    const current = selectedClock(currentValue);
    const options = [{ value: '__none__', label: '(none)' }];
    if (!runtime.irMeta) {
      return {
        options,
        selected: '__none__'
      };
    }

    const clocks = runtime.irMeta.clockCandidates || runtime.irMeta.clocks || [];
    for (const clk of clocks) {
      let label = clk;
      if (runtime.sim) {
        const mode = runtime.sim.clock_mode(clk);
        label = `${clk} (${mode})`;
      }
      options.push({ value: clk, label });
    }

    if (current && clocks.includes(current)) {
      return { options, selected: current };
    }

    if (clocks.length > 0) {
      const preset = currentRunnerPreset();
      if (preset.id === 'apple2' && clocks.includes('clk_14m')) {
        return { options, selected: 'clk_14m' };
      }
      const preferred = clocks.find((clk) => /^(clk|clock)$/i.test(clk));
      return { options, selected: preferred || clocks[0] };
    }

    return {
      options,
      selected: '__none__'
    };
  }

  return {
    selectedClock,
    maskForWidth,
    describeStatus,
    listClockOptions
  };
}
