function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimStatusController requires function: ${name}`);
  }
}

export function createSimStatusController({
  dom,
  state,
  runtime,
  getBackendDef,
  currentRunnerPreset,
  isApple2UiEnabled,
  updateIoToggleUi,
  scheduleReduxUxSync,
  litRender,
  html
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createSimStatusController requires dom/state/runtime');
  }
  requireFn('getBackendDef', getBackendDef);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);
  requireFn('updateIoToggleUi', updateIoToggleUi);
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('litRender', litRender);
  requireFn('html', html);

  function selectedClock() {
    const val = dom.clockSignal.value;
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

  function refreshStatus() {
    const backendDef = getBackendDef(state.backend);
    if (!runtime.sim) {
      dom.simStatus.textContent = 'Simulator not initialized';
      dom.traceStatus.textContent = 'Trace disabled';
      if (dom.backendStatus) {
        dom.backendStatus.textContent = `Backend: ${backendDef.id}`;
      }
      if (dom.runnerStatus) {
        dom.runnerStatus.textContent = 'Runner not initialized';
      }
      scheduleReduxUxSync('refreshStatus:no-sim');
      return;
    }

    const sigs = runtime.sim.signal_count();
    const regs = runtime.sim.reg_count();
    const clk = selectedClock();
    const mode = clk ? runtime.sim.clock_mode(clk) : null;
    const clockPart = clk ? ` | clock ${clk}${mode && mode !== 'unknown' ? ` (${mode})` : ''}` : '';
    dom.simStatus.textContent = `Cycle ${state.cycle} | ${sigs} signals | ${regs} regs${clockPart} ${state.running ? '| RUNNING' : '| PAUSED'}`;
    dom.traceStatus.textContent = `Trace ${runtime.sim.trace_enabled() ? 'enabled' : 'disabled'} | changes ${runtime.sim.trace_change_count()}`;
    if (dom.backendStatus) {
      const notes = [];
      if (!runtime.sim.features.hasSignalIndex) {
        notes.push('name-mode');
      }
      if (!runtime.sim.features.hasLiveTrace) {
        notes.push('vcd-snapshot');
      }
      dom.backendStatus.textContent = `Backend: ${backendDef.id}${notes.length > 0 ? ` (${notes.join(', ')})` : ''}`;
    }

    if (dom.runnerStatus) {
      const preset = currentRunnerPreset();
      const apple2Flag = runtime.sim.apple2_mode() ? ' | apple2 mode' : '';
      dom.runnerStatus.textContent = `${preset.label}${apple2Flag} | ${backendDef.label}`;
    }

    if (isApple2UiEnabled() && dom.apple2KeyStatus) {
      dom.apple2KeyStatus.textContent = `Keyboard queue: ${state.apple2.keyQueue.length}`;
    }

    updateIoToggleUi();
    scheduleReduxUxSync('refreshStatus');
  }

  function populateClockSelect() {
    const current = dom.clockSignal.value;
    const options = [{ value: '__none__', label: '(none)' }];
    if (!runtime.irMeta) {
      litRender(html`${options.map((entry) => html`
        <option value=${entry.value}>${entry.label}</option>
      `)}`, dom.clockSignal);
      return;
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

    litRender(html`${options.map((entry) => html`
      <option value=${entry.value}>${entry.label}</option>
    `)}`, dom.clockSignal);

    if (current && clocks.includes(current)) {
      dom.clockSignal.value = current;
      return;
    }

    if (clocks.length > 0) {
      const preset = currentRunnerPreset();
      if (preset.id === 'apple2' && clocks.includes('clk_14m')) {
        dom.clockSignal.value = 'clk_14m';
        return;
      }
      const preferred = clocks.find((clk) => /^(clk|clock)$/i.test(clk));
      dom.clockSignal.value = preferred || clocks[0];
    }
  }

  return {
    selectedClock,
    maskForWidth,
    refreshStatus,
    populateClockSelect
  };
}
