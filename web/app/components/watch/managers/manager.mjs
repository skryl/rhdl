function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createWatchManager requires function: ${name}`);
  }
}

export function createWatchManager({
  dom,
  state,
  runtime,
  appStore,
  storeActions,
  formatValue,
  parseNumeric,
  maskForWidth,
  toBigInt,
  log,
  scheduleReduxUxSync,
  renderWatchTableRows,
  renderWatchListItems,
  renderBreakpointListItems
} = {}) {
  if (!dom || !state || !runtime || !appStore || !storeActions) {
    throw new Error('createWatchManager requires dom, state, runtime, appStore, and storeActions');
  }

  requireFn('formatValue', formatValue);
  requireFn('parseNumeric', parseNumeric);
  requireFn('maskForWidth', maskForWidth);
  requireFn('toBigInt', toBigInt);
  requireFn('log', log);
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('renderWatchTableRows', renderWatchTableRows);
  requireFn('renderWatchListItems', renderWatchListItems);
  requireFn('renderBreakpointListItems', renderBreakpointListItems);

  function refreshWatchTable() {
    if (!runtime.sim) {
      renderWatchTableRows(dom, [], formatValue);
      state.watchRows = [];
      return;
    }

    const rows = [];
    for (const [name, info] of state.watches.entries()) {
      const value = info.idx != null ? runtime.sim.peek_by_idx(info.idx) : runtime.sim.peek(name);
      rows.push({ name, width: info.width, idx: info.idx, value });
    }

    state.watchRows = rows;
    renderWatchTableRows(dom, rows, formatValue);
  }

  function renderWatchList() {
    const names = Array.from(state.watches.keys());
    renderWatchListItems(dom, names);
    scheduleReduxUxSync('renderWatchList');
  }

  function renderBreakpointList() {
    renderBreakpointListItems(dom, state.breakpoints, formatValue);
    scheduleReduxUxSync('renderBreakpointList');
  }

  function addWatchSignal(name) {
    if (!runtime.sim || !name) {
      return false;
    }

    if (state.watches.has(name)) {
      return false;
    }

    let idx = null;
    if (runtime.sim.features.hasSignalIndex) {
      const resolved = runtime.sim.get_signal_idx(name);
      if (resolved < 0) {
        log(`Unknown signal: ${name}`);
        return false;
      }
      idx = resolved;
    } else if (!runtime.sim.has_signal(name)) {
      log(`Unknown signal: ${name}`);
      return false;
    }

    const width = runtime.irMeta?.widths.get(name) || 1;
    appStore.dispatch(storeActions.watchSet(name, { idx, width }));
    runtime.sim.trace_add_signal(name);
    refreshWatchTable();
    renderWatchList();
    scheduleReduxUxSync('addWatchSignal');
    return true;
  }

  function removeWatchSignal(name) {
    const had = state.watches instanceof Map && state.watches.has(name);
    appStore.dispatch(storeActions.watchRemove(name));
    if (!had) {
      return false;
    }
    refreshWatchTable();
    renderWatchList();
    scheduleReduxUxSync('removeWatchSignal');
    return true;
  }

  function clearAllWatches() {
    appStore.dispatch(storeActions.watchClear());
    refreshWatchTable();
    renderWatchList();
  }

  function addBreakpointSignal(signal, valueRaw) {
    if (!runtime.sim) {
      throw new Error('Simulator not initialized.');
    }
    const parsed = parseNumeric(valueRaw);
    if (parsed == null) {
      throw new Error(`Invalid breakpoint value: ${valueRaw}`);
    }

    let idx = null;
    if (runtime.sim.features.hasSignalIndex) {
      const resolved = runtime.sim.get_signal_idx(signal);
      if (resolved < 0) {
        throw new Error(`Unknown signal: ${signal}`);
      }
      idx = resolved;
    } else if (!runtime.sim.has_signal(signal)) {
      throw new Error(`Unknown signal: ${signal}`);
    }

    const width = runtime.irMeta?.widths.get(signal) || 1;
    const mask = maskForWidth(width);
    const value = parsed & mask;
    appStore.dispatch(storeActions.breakpointAddOrReplace({ name: signal, idx, width, value }));
    renderBreakpointList();
    return value;
  }

  function clearAllBreakpoints() {
    appStore.dispatch(storeActions.breakpointClear());
    renderBreakpointList();
  }

  function checkBreakpoints() {
    for (const bp of state.breakpoints) {
      const current = toBigInt(bp.idx != null ? runtime.sim.peek_by_idx(bp.idx) : runtime.sim.peek(bp.name));
      if (current === bp.value) {
        return { signal: bp.name, value: current };
      }
    }
    return null;
  }

  return {
    refreshWatchTable,
    renderWatchList,
    renderBreakpointList,
    addWatchSignal,
    removeWatchSignal,
    clearAllWatches,
    addBreakpointSignal,
    clearAllBreakpoints,
    checkBreakpoints
  };
}
