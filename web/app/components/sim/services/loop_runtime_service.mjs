export function normalizeApple2KeyCode(value) {
  if (value == null) {
    return null;
  }
  let ascii = typeof value === 'number' ? value : String(value).charCodeAt(0);
  if (!Number.isFinite(ascii)) {
    return null;
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
  return ascii & 0xff;
}

function parsePositiveInt(raw, fallback) {
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(1, parsed);
}

export function parseStepTickCount(rawValue) {
  return parsePositiveInt(rawValue, 1);
}

export function parseRunLoopConfig({ runBatchRaw, uiUpdateCyclesRaw } = {}) {
  const batch = parsePositiveInt(runBatchRaw, 20000);
  const uiEvery = parsePositiveInt(uiUpdateCyclesRaw, batch);
  return { batch, uiEvery };
}

export function executeGenericRunBatch({
  runtime,
  state,
  batch,
  selectedClock,
  setCycleState,
  checkBreakpoints
} = {}) {
  let hit = null;
  let cyclesRan = 0;
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
  return { cyclesRan, hit };
}

export function shouldRefreshUiAfterRun({
  state,
  hit,
  uiEvery,
  isComponentTabActive
} = {}) {
  return !state.running
    || !!hit
    || state.uiCyclesPending >= uiEvery
    || state.activeTab === 'memoryTab'
    || isComponentTabActive();
}
