function requireFn(name: Unsafe, fn: Unsafe) {
  if (typeof fn !== 'function') {
    throw new Error(`createSimStatusRuntimeService requires function: ${name}`);
  }
}

function parsePositiveNumber(value: Unsafe, fallback: Unsafe) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return fallback;
  }
  return parsed;
}

function formatRate(value: Unsafe) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return '0';
  }
  if (numeric >= 100) {
    return Math.round(numeric).toLocaleString('en-US');
  }
  if (numeric >= 10) {
    return numeric.toFixed(1);
  }
  return numeric.toFixed(2);
}

function resolveTimingConfig(preset: Unsafe = {}) {
  const raw = preset?.timing && typeof preset.timing === 'object' ? preset.timing : {};
  return {
    cyclesPerHertz: parsePositiveNumber(raw.cyclesPerHertz, 1),
    hertzLabel: String(raw.hertzLabel || 'CPU').trim() || 'CPU'
  };
}

function resolveSignalCount(runtime: Unsafe): number {
  let reported = 0;
  if (runtime?.sim && typeof runtime.sim.signal_count === 'function') {
    try {
      const value = Number(runtime.sim.signal_count());
      if (Number.isFinite(value) && value > 0) {
        return value;
      }
      if (Number.isFinite(value) && value >= 0) {
        reported = value;
      }
    } catch {
      reported = 0;
    }
  }

  const metaNames = runtime?.irMeta?.names;
  if (Array.isArray(metaNames) && metaNames.length > 0) {
    return metaNames.length;
  }

  const widths = runtime?.irMeta?.widths;
  if (widths instanceof Map && widths.size > 0) {
    return widths.size;
  }

  return Math.max(0, reported | 0);
}

export function createSimStatusRuntimeService({
  state,
  runtime,
  getBackendDef,
  currentRunnerPreset,
  isApple2UiEnabled
}: Unsafe = {}) {
  if (!state || !runtime) {
    throw new Error('createSimStatusRuntimeService requires state/runtime');
  }
  requireFn('getBackendDef', getBackendDef);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('isApple2UiEnabled', isApple2UiEnabled);

  function selectedClock(value: Unsafe) {
    const val = String(value || '').trim();
    if (!val || val === '__none__') {
      return null;
    }
    return val;
  }

  function maskForWidth(width: Unsafe) {
    if (width >= 64) {
      return (1n << 64n) - 1n;
    }
    return (1n << BigInt(width)) - 1n;
  }

  function describeStatus(clockValue: Unsafe) {
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

    const sigs = resolveSignalCount(runtime);
    const regs = runtime.sim.reg_count();
    const clk = selectedClock(clockValue);
    const mode = clk ? runtime.sim.clock_mode(clk) : null;
    const clockPart = clk ? ` | clock ${clk}${mode && mode !== 'unknown' ? ` (${mode})` : ''}` : '';
    const preset = currentRunnerPreset();
    const timing = resolveTimingConfig(preset);
    const cyclesPerSecond = Math.max(0, Number(runtime.throughput?.cyclesPerSecond) || 0);
    const cpuHertz = cyclesPerSecond / timing.cyclesPerHertz;
    const simStatus =
      `Cycle ${state.cycle} | ${sigs} signals | ${regs} regs` +
      `${clockPart} | ${formatRate(cyclesPerSecond)} cyc/s | ${formatRate(cpuHertz)} ${timing.hertzLabel} Hz` +
      ` ${state.running ? '| RUNNING' : '| PAUSED'}`;
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

    const apple2Flag = runtime.sim.runner_kind?.() === 'apple2' ? ' | apple2 mode' : '';
    const memoryMode = typeof runtime.sim.memory_mode === 'function' ? runtime.sim.memory_mode() : null;
    const memoryFlag = memoryMode && !apple2Flag ? ` | ${memoryMode} memory API` : '';
    const runnerStatus = `${preset.label}${apple2Flag}${memoryFlag} | ${backendDef.label}`;

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

  function listClockOptions(currentValue: Unsafe) {
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
      const preferred = clocks.find((clk: Unsafe) => /^(clk|clock)$/i.test(clk));
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
