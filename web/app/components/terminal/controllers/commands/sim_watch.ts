export async function handleSimWatchCommand({ cmd, tokens, context }) {
  const { dom, state, runtime, actions, helpers } = context;

  if (cmd === 'init') {
    await actions.initializeSimulator();
    return 'simulator initialized';
  }
  if (cmd === 'reset') {
    dom.resetBtn?.click();
    return 'simulator reset';
  }
  if (cmd === 'step') {
    if (tokens[0]) {
      helpers.setUiInputValueById('stepTicks', tokens[0]);
    }
    actions.stepSimulation();
    return `stepped ${dom.stepTicks?.value || '1'} tick(s)`;
  }
  if (cmd === 'run') {
    dom.runBtn?.click();
    return 'run started';
  }
  if (cmd === 'pause') {
    dom.pauseBtn?.click();
    return 'run paused';
  }
  if (cmd === 'clock') {
    const value = String(tokens[0] || '').trim();
    if (!value) {
      throw new Error('Usage: clock <signal|none>');
    }
    const next = value.toLowerCase() === 'none' ? '__none__' : value;
    if (!dom.clockSignal) {
      throw new Error('Clock selector unavailable.');
    }
    const hasOption = Array.from(dom.clockSignal.options).some((opt) => opt.value === next);
    if (!hasOption) {
      throw new Error(`Unknown clock signal: ${next}`);
    }
    dom.clockSignal.value = next;
    helpers.dispatchBubbledEvent(dom.clockSignal, 'change');
    return `clock=${next === '__none__' ? '(none)' : next}`;
  }
  if (cmd === 'batch') {
    if (!tokens[0]) {
      throw new Error('Usage: batch <n>');
    }
    return helpers.setUiInputValueById('runBatch', tokens[0]);
  }
  if (cmd === 'ui_every' || cmd === 'ui-every' || cmd === 'uievery') {
    if (!tokens[0]) {
      throw new Error('Usage: ui_every <n>');
    }
    return helpers.setUiInputValueById('uiUpdateCycles', tokens[0]);
  }

  if (cmd === 'trace') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'start') {
      dom.traceStartBtn?.click();
      return 'trace started';
    }
    if (sub === 'stop') {
      dom.traceStopBtn?.click();
      return 'trace stopped';
    }
    if (sub === 'clear') {
      dom.traceClearBtn?.click();
      return 'trace cleared';
    }
    if (sub === 'save') {
      dom.downloadVcdBtn?.click();
      return 'trace save started';
    }
    throw new Error('Usage: trace <start|stop|clear|save>');
  }

  if (cmd === 'watch') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'add') {
      const signal = String(tokens[1] || '').trim();
      if (!signal) {
        throw new Error('Usage: watch add <signal>');
      }
      const ok = actions.addWatchSignal(signal);
      if (!ok) {
        throw new Error(`Could not add watch: ${signal}`);
      }
      return `watch added: ${signal}`;
    }
    if (sub === 'remove' || sub === 'rm' || sub === 'del') {
      const signal = String(tokens[1] || '').trim();
      if (!signal) {
        throw new Error('Usage: watch remove <signal>');
      }
      const ok = actions.removeWatchSignal(signal);
      if (!ok) {
        throw new Error(`Watch not found: ${signal}`);
      }
      return `watch removed: ${signal}`;
    }
    if (sub === 'clear') {
      actions.clearAllWatches();
      return 'watches cleared';
    }
    if (sub === 'list') {
      const names = Array.from(state.watches.keys());
      return names.length > 0 ? names.join('\n') : '(no watches)';
    }
    throw new Error('Usage: watch <add|remove|clear|list> ...');
  }

  if (cmd === 'bp' || cmd === 'breakpoint') {
    const sub = String(tokens[0] || '').toLowerCase();
    if (sub === 'add') {
      const signal = String(tokens[1] || '').trim();
      const valueRaw = String(tokens[2] || '').trim();
      if (!signal || !valueRaw) {
        throw new Error('Usage: bp add <signal> <value>');
      }
      const value = actions.addBreakpointSignal(signal, valueRaw);
      return `breakpoint added: ${signal}=${actions.formatValue(value, 64)}`;
    }
    if (sub === 'remove' || sub === 'rm' || sub === 'del') {
      const signal = String(tokens[1] || '').trim();
      if (!signal) {
        throw new Error('Usage: bp remove <signal>');
      }
      actions.replaceBreakpointsState(state.breakpoints.filter((bp) => bp.name !== signal));
      actions.renderBreakpointList();
      return `breakpoint removed: ${signal}`;
    }
    if (sub === 'clear') {
      actions.clearAllBreakpoints();
      return 'breakpoints cleared';
    }
    if (sub === 'list') {
      return state.breakpoints.length > 0
        ? state.breakpoints.map((bp) => `${bp.name}=${actions.formatValue(bp.value, bp.width)}`).join('\n')
        : '(no breakpoints)';
    }
    throw new Error('Usage: bp <add|remove|clear|list> ...');
  }

  if (cmd === 'key') {
    const raw = String(tokens[0] || '').toLowerCase();
    if (!raw) {
      throw new Error('Usage: key <char|enter|backspace>');
    }
    if (raw === 'enter') {
      actions.queueApple2Key('\r');
      return 'key queued: ENTER';
    }
    if (raw === 'backspace') {
      actions.queueApple2Key(String.fromCharCode(0x08));
      return 'key queued: BACKSPACE';
    }
    actions.queueApple2Key(tokens[0][0]);
    return `key queued: ${tokens[0][0]}`;
  }

  return undefined;
}
