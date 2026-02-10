import { parseHexOrDec } from '../../../core/lib/numeric_utils.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2SimRuntimeService requires function: ${name}`);
  }
}

export function createApple2SimRuntimeService({
  state,
  runtime,
  APPLE2_RAM_BYTES,
  setRunningState,
  setCycleState,
  setUiCyclesPendingState,
  getApple2ProgramCounter,
  ensureApple2Ready,
  setMemoryDumpStatus,
  refreshApple2UiState,
  log
} = {}) {
  if (!state || !runtime) {
    throw new Error('createApple2SimRuntimeService requires state/runtime');
  }
  const defaultRamBytes = Number.isFinite(APPLE2_RAM_BYTES) && APPLE2_RAM_BYTES > 0
    ? APPLE2_RAM_BYTES
    : 0x10000;
  requireFn('setRunningState', setRunningState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('ensureApple2Ready', ensureApple2Ready);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('refreshApple2UiState', refreshApple2UiState);
  requireFn('log', log);

  function currentMemoryConfig() {
    return state.apple2?.ioConfig?.memory || {};
  }

  function currentAddressSpace() {
    const configured = Number.parseInt(currentMemoryConfig().addressSpace, 10);
    if (Number.isFinite(configured) && configured > 0) {
      return configured;
    }
    return defaultRamBytes;
  }

  function fitApple2RamWindow(bytes, offset) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return { data: new Uint8Array(0), trimmed: false };
    }
    const off = Math.max(0, Math.trunc(offset));
    const maxWindow = currentAddressSpace();
    if (off >= maxWindow) {
      return { data: new Uint8Array(0), trimmed: true };
    }
    const maxLen = maxWindow - off;
    if (bytes.length <= maxLen) {
      return { data: bytes, trimmed: false };
    }
    return { data: bytes.subarray(0, maxLen), trimmed: true };
  }

  function performApple2ResetSequence(options = {}) {
    if (!runtime.sim) {
      return { pcBefore: null, pcAfter: null, releaseCycles: 0, usedResetSignal: false };
    }
    setRunningState(false);
    state.apple2.keyQueue = [];
    const parsedReleaseCycles = Number.parseInt(options.releaseCycles, 10);
    const releaseCycles = Number.isFinite(parsedReleaseCycles) ? Math.max(0, parsedReleaseCycles) : 10;
    const pcBefore = getApple2ProgramCounter();
    let usedResetSignal = false;
    const runResetCycles = (cycles) => {
      if (typeof runtime.sim.runner_run_cycles === 'function') {
        runtime.sim.runner_run_cycles(cycles, 0, false);
        return;
      }
      if (typeof runtime.sim.run_ticks === 'function') {
        runtime.sim.run_ticks(cycles);
      }
    };

    if (runtime.sim.has_signal('reset')) {
      usedResetSignal = true;
      runtime.sim.poke('reset', 1);
      runResetCycles(1);
      runtime.sim.poke('reset', 0);
      if (releaseCycles > 0) {
        runResetCycles(releaseCycles);
      }
    } else {
      runtime.sim.reset();
    }

    setCycleState(0);
    setUiCyclesPendingState(0);
    if (runtime.sim.trace_enabled()) {
      runtime.sim.trace_capture();
    }
    const pcAfter = getApple2ProgramCounter();
    return { pcBefore, pcAfter, releaseCycles, usedResetSignal };
  }

  async function loadApple2MemoryDumpBytes(bytes, offset, options = {}) {
    if (!ensureApple2Ready()) {
      return false;
    }

    const off = Math.max(0, parseHexOrDec(offset, 0));
    const source = bytes instanceof Uint8Array ? bytes : new Uint8Array(0);
    const { data, trimmed } = fitApple2RamWindow(source, off);

    if (data.length === 0) {
      setMemoryDumpStatus('No bytes loaded (offset out of RAM window).');
      return false;
    }

    const ok = typeof runtime.sim.memory_load === 'function'
      ? runtime.sim.memory_load(data, off, { isRom: false })
      : (typeof runtime.sim.runner_load_memory === 'function'
          ? runtime.sim.runner_load_memory(data, off, { isRom: false })
          : false);
    if (!ok) {
      setMemoryDumpStatus('Dump load failed (runner memory API unavailable).');
      return false;
    }

    if (options.resetAfterLoad) {
      const parsedResetReleaseCycles = Number.parseInt(options.resetReleaseCycles, 10);
      const resetReleaseCycles = Number.isFinite(parsedResetReleaseCycles)
        ? Math.max(0, parsedResetReleaseCycles)
        : 0;
      performApple2ResetSequence({ releaseCycles: resetReleaseCycles });
    }

    refreshApple2UiState();

    const label = options.label || 'memory dump';
    const suffix = trimmed ? ` (trimmed to ${data.length} bytes)` : '';
    const msg = `Loaded ${label} at $${off.toString(16).toUpperCase().padStart(4, '0')} (${data.length} bytes)${suffix}`;
    setMemoryDumpStatus(msg);
    log(msg);
    return true;
  }

  return {
    fitApple2RamWindow,
    performApple2ResetSequence,
    loadApple2MemoryDumpBytes
  };
}
