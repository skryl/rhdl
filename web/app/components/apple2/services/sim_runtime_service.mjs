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
  if (!Number.isFinite(APPLE2_RAM_BYTES) || APPLE2_RAM_BYTES <= 0) {
    throw new Error('createApple2SimRuntimeService requires APPLE2_RAM_BYTES');
  }
  requireFn('setRunningState', setRunningState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('ensureApple2Ready', ensureApple2Ready);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('refreshApple2UiState', refreshApple2UiState);
  requireFn('log', log);

  function fitApple2RamWindow(bytes, offset) {
    if (!(bytes instanceof Uint8Array) || bytes.length === 0) {
      return { data: new Uint8Array(0), trimmed: false };
    }
    const off = Math.max(0, Math.trunc(offset));
    if (off >= APPLE2_RAM_BYTES) {
      return { data: new Uint8Array(0), trimmed: true };
    }
    const maxLen = APPLE2_RAM_BYTES - off;
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

    if (runtime.sim.has_signal('reset')) {
      usedResetSignal = true;
      runtime.sim.poke('reset', 1);
      runtime.sim.apple2_run_cpu_cycles(1, 0, false);
      runtime.sim.poke('reset', 0);
      if (releaseCycles > 0) {
        runtime.sim.apple2_run_cpu_cycles(releaseCycles, 0, false);
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

    const ok = runtime.sim.apple2_load_ram(data, off);
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
