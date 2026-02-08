import { tokenizeCommandLine, parseBooleanToken } from '../lib/terminal_tokens.mjs';

export function normalizeUiId(value) {
  return String(value || '').trim().replace(/^#/, '');
}

export function parseTabToken(token, tabPanels = []) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  const map = {
    io: 'ioTab',
    'i/o': 'ioTab',
    vcd: 'vcdTab',
    signals: 'vcdTab',
    memory: 'memoryTab',
    mem: 'memoryTab',
    component: 'componentTab',
    components: 'componentTab',
    comp: 'componentTab',
    schematic: 'componentGraphTab',
    graph: 'componentGraphTab'
  };
  if (map[raw]) {
    return map[raw];
  }
  if (Array.isArray(tabPanels) && tabPanels.some((panel) => panel && panel.id === token)) {
    return token;
  }
  return null;
}

export function parseRunnerToken(token, runnerPresets) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (runnerPresets && runnerPresets[raw]) {
    return runnerPresets[raw].id;
  }
  if (raw === 'apple' || raw === 'apple2') {
    return 'apple2';
  }
  return null;
}

export function parseBackendToken(token, backendDefs) {
  const raw = String(token || '').trim().toLowerCase();
  if (!raw) {
    return null;
  }
  if (backendDefs && backendDefs[raw]) {
    return backendDefs[raw].id;
  }
  return null;
}

export function terminalHelpText() {
  return [
    'Commands:',
    '  help',
    '  status',
    '  config <show|hide|toggle>',
    '  terminal <show|hide|toggle|clear>',
    '  tab <io|vcd|memory|components|schematic>',
    '  runner <generic|cpu|apple2> [load]',
    '  backend <interpreter|jit|compiler>',
    '  theme <shenzhen|original>',
    '  init | reset | step [n] | run | pause',
    '  clock <signal|none>',
    '  batch <n> | ui_every <n>',
    '  trace <start|stop|clear|save>',
    '  watch <add NAME|remove NAME|clear|list>',
    '  bp <add NAME VALUE|remove NAME|clear|list>',
    '  io <hires|color|sound> <on|off|toggle>',
    '  key <char|enter|backspace>',
    '  memory view [start] [len]',
    '  memory followpc <on|off|toggle>',
    '  memory write <addr> <value>',
    '  memory reset [vector]',
    '  memory <karateka|load_last|save_dump|save_snapshot|load_selected>',
    '  sample [path]  (generic runner)',
    '  set <elementId> <value>  (generic UI setter)',
    '  click <elementId>        (generic UI button click)'
  ].join('\n');
}

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createTerminalCommandController requires function: ${name}`);
  }
}

export function createTerminalCommandController({
  dom,
  state,
  runtime,
  backendDefs,
  runnerPresets,
  actions = {},
  documentRef = globalThis.document,
  eventCtor = globalThis.Event,
  requestFrame = globalThis.requestAnimationFrame || ((cb) => setTimeout(cb, 0))
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createTerminalCommandController requires dom, state, and runtime');
  }

  requireFn('actions.currentRunnerPreset', actions.currentRunnerPreset);
  requireFn('actions.getBackendDef', actions.getBackendDef);
  requireFn('actions.setSidebarCollapsed', actions.setSidebarCollapsed);
  requireFn('actions.setTerminalOpen', actions.setTerminalOpen);
  requireFn('actions.setActiveTab', actions.setActiveTab);
  requireFn('actions.setRunnerPresetState', actions.setRunnerPresetState);
  requireFn('actions.updateIrSourceVisibility', actions.updateIrSourceVisibility);
  requireFn('actions.loadRunnerPreset', actions.loadRunnerPreset);
  requireFn('actions.refreshStatus', actions.refreshStatus);
  requireFn('actions.applyTheme', actions.applyTheme);
  requireFn('actions.loadSample', actions.loadSample);
  requireFn('actions.initializeSimulator', actions.initializeSimulator);
  requireFn('actions.stepSimulation', actions.stepSimulation);
  requireFn('actions.addWatchSignal', actions.addWatchSignal);
  requireFn('actions.removeWatchSignal', actions.removeWatchSignal);
  requireFn('actions.clearAllWatches', actions.clearAllWatches);
  requireFn('actions.addBreakpointSignal', actions.addBreakpointSignal);
  requireFn('actions.clearAllBreakpoints', actions.clearAllBreakpoints);
  requireFn('actions.replaceBreakpointsState', actions.replaceBreakpointsState);
  requireFn('actions.renderBreakpointList', actions.renderBreakpointList);
  requireFn('actions.setMemoryFollowPcState', actions.setMemoryFollowPcState);
  requireFn('actions.refreshMemoryView', actions.refreshMemoryView);
  requireFn('actions.resetApple2WithMemoryVectorOverride', actions.resetApple2WithMemoryVectorOverride);
  requireFn('actions.loadKaratekaDump', actions.loadKaratekaDump);
  requireFn('actions.loadLastSavedApple2Dump', actions.loadLastSavedApple2Dump);
  requireFn('actions.saveApple2MemoryDump', actions.saveApple2MemoryDump);
  requireFn('actions.saveApple2MemorySnapshot', actions.saveApple2MemorySnapshot);
  requireFn('actions.queueApple2Key', actions.queueApple2Key);
  requireFn('actions.formatValue', actions.formatValue);

  function dispatchBubbledEvent(target, type) {
    if (!target || typeof target.dispatchEvent !== 'function' || typeof eventCtor !== 'function') {
      return;
    }
    target.dispatchEvent(new eventCtor(type, { bubbles: true }));
  }

  function terminalWriteLine(message = '') {
    if (!dom.terminalOutput) {
      return;
    }
    const text = String(message ?? '');
    dom.terminalOutput.textContent += `${text}\n`;
    const lines = dom.terminalOutput.textContent.split('\n');
    if (lines.length > 900) {
      dom.terminalOutput.textContent = `${lines.slice(lines.length - 900).join('\n')}\n`;
    }
    dom.terminalOutput.scrollTop = dom.terminalOutput.scrollHeight;
  }

  function terminalClear() {
    if (!dom.terminalOutput) {
      return;
    }
    dom.terminalOutput.textContent = '';
  }

  function setUiInputValueById(id, value) {
    const elementId = normalizeUiId(id);
    if (!elementId) {
      throw new Error('Missing element id.');
    }
    const el = documentRef.getElementById(elementId);
    if (!(el instanceof HTMLElement)) {
      throw new Error(`Unknown element: ${elementId}`);
    }

    if (el instanceof HTMLInputElement && el.type === 'checkbox') {
      const parsed = parseBooleanToken(value);
      if (parsed == null) {
        throw new Error(`Invalid checkbox value for ${elementId}: ${value}`);
      }
      el.checked = parsed;
      dispatchBubbledEvent(el, 'change');
      return `set #${elementId}= ${parsed ? 'on' : 'off'}`;
    }

    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
      el.value = String(value ?? '');
      dispatchBubbledEvent(el, 'input');
      if (el instanceof HTMLInputElement && (el.type === 'number' || el.type === 'range')) {
        dispatchBubbledEvent(el, 'change');
      }
      return `set #${elementId}= ${el.value}`;
    }

    if (el instanceof HTMLSelectElement) {
      const next = String(value ?? '');
      const hasOption = Array.from(el.options).some((opt) => opt.value === next);
      if (!hasOption) {
        const options = Array.from(el.options).map((opt) => opt.value).join(', ');
        throw new Error(`Invalid option for ${elementId}. Available: ${options}`);
      }
      el.value = next;
      dispatchBubbledEvent(el, 'change');
      return `set #${elementId}= ${el.value}`;
    }

    throw new Error(`Element does not support value assignment: ${elementId}`);
  }

  function clickUiElementById(id) {
    const elementId = normalizeUiId(id);
    if (!elementId) {
      throw new Error('Missing element id.');
    }
    const el = documentRef.getElementById(elementId);
    if (!(el instanceof HTMLElement)) {
      throw new Error(`Unknown element: ${elementId}`);
    }
    if (typeof el.click !== 'function') {
      throw new Error(`Element is not clickable: ${elementId}`);
    }
    el.click();
    return `clicked #${elementId}`;
  }

  function terminalStatusText() {
    const runner = actions.currentRunnerPreset();
    const backend = actions.getBackendDef(state.backend);
    const tab = state.activeTab || '-';
    const sim = runtime.sim ? 'ready' : 'not-initialized';
    const trace = runtime.sim ? (runtime.sim.trace_enabled() ? 'on' : 'off') : 'n/a';
    return [
      `runner=${runner.id}`,
      `backend=${backend.id}`,
      `tab=${tab}`,
      `sim=${sim}`,
      `running=${state.running ? 'yes' : 'no'}`,
      `cycle=${state.cycle}`,
      `trace=${trace}`,
      `watches=${state.watches.size}`,
      `breakpoints=${state.breakpoints.length}`
    ].join(' ');
  }

  async function executeTerminalCommand(rawLine) {
    const tokens = tokenizeCommandLine(rawLine);
    if (tokens.length === 0) {
      return null;
    }
    const cmd = tokens.shift().toLowerCase();

    if (cmd === 'help' || cmd === '?') {
      return terminalHelpText();
    }
    if (cmd === 'status') {
      return terminalStatusText();
    }
    if (cmd === 'clear') {
      terminalClear();
      return null;
    }

    if (cmd === 'config') {
      const mode = String(tokens[0] || 'toggle').toLowerCase();
      if (mode === 'toggle') {
        actions.setSidebarCollapsed(!state.sidebarCollapsed);
      } else {
        const desired = parseBooleanToken(mode);
        if (desired == null) {
          throw new Error('Usage: config <show|hide|toggle>');
        }
        actions.setSidebarCollapsed(!desired);
      }
      return `config ${state.sidebarCollapsed ? 'hidden' : 'visible'}`;
    }

    if (cmd === 'terminal') {
      const mode = String(tokens[0] || 'toggle').toLowerCase();
      if (mode === 'clear') {
        terminalClear();
        return null;
      }
      if (mode === 'toggle') {
        actions.setTerminalOpen(!state.terminalOpen, { focus: true });
      } else {
        const desired = parseBooleanToken(mode);
        if (desired == null) {
          throw new Error('Usage: terminal <show|hide|toggle|clear>');
        }
        actions.setTerminalOpen(desired, { focus: desired });
      }
      return `terminal ${state.terminalOpen ? 'open' : 'closed'}`;
    }

    if (cmd === 'tab') {
      const tabId = parseTabToken(tokens[0], dom.tabPanels);
      if (!tabId) {
        throw new Error('Usage: tab <io|vcd|memory|components|schematic>');
      }
      actions.setActiveTab(tabId);
      return `tab=${tabId}`;
    }

    if (cmd === 'runner') {
      const runnerId = parseRunnerToken(tokens[0], runnerPresets);
      if (!runnerId) {
        throw new Error('Usage: runner <generic|cpu|apple2> [load]');
      }
      actions.setRunnerPresetState(runnerId);
      if (dom.runnerSelect) {
        dom.runnerSelect.value = runnerId;
      }
      actions.updateIrSourceVisibility();
      const doLoad = tokens.length < 2 || String(tokens[1] || '').toLowerCase() !== 'select';
      if (doLoad) {
        await actions.loadRunnerPreset();
        return `runner loaded: ${runnerId}`;
      }
      actions.refreshStatus();
      return `runner selected: ${runnerId}`;
    }

    if (cmd === 'backend') {
      const backendId = parseBackendToken(tokens[0], backendDefs);
      if (!backendId) {
        throw new Error('Usage: backend <interpreter|jit|compiler>');
      }
      if (dom.backendSelect) {
        dom.backendSelect.value = backendId;
        dispatchBubbledEvent(dom.backendSelect, 'change');
      }
      return `backend change requested: ${backendId}`;
    }

    if (cmd === 'theme') {
      const theme = String(tokens[0] || '').toLowerCase();
      if (!['shenzhen', 'original'].includes(theme)) {
        throw new Error('Usage: theme <shenzhen|original>');
      }
      actions.applyTheme(theme);
      return `theme=${theme}`;
    }

    if (cmd === 'sample') {
      if (!actions.currentRunnerPreset().usesManualIr) {
        throw new Error('Sample command is only available on the generic runner.');
      }
      if (tokens[0]) {
        if (!dom.sampleSelect) {
          throw new Error('Sample selector unavailable.');
        }
        const samplePath = tokens[0];
        const exists = Array.from(dom.sampleSelect.options).some((opt) => opt.value === samplePath);
        if (!exists) {
          throw new Error(`Unknown sample: ${samplePath}`);
        }
        dom.sampleSelect.value = samplePath;
      }
      await actions.loadSample();
      return `sample loaded: ${dom.sampleSelect?.value || ''}`;
    }

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
        setUiInputValueById('stepTicks', tokens[0]);
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
      dispatchBubbledEvent(dom.clockSignal, 'change');
      return `clock=${next === '__none__' ? '(none)' : next}`;
    }
    if (cmd === 'batch') {
      if (!tokens[0]) {
        throw new Error('Usage: batch <n>');
      }
      return setUiInputValueById('runBatch', tokens[0]);
    }
    if (cmd === 'ui_every' || cmd === 'ui-every' || cmd === 'uievery') {
      if (!tokens[0]) {
        throw new Error('Usage: ui_every <n>');
      }
      return setUiInputValueById('uiUpdateCycles', tokens[0]);
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

    if (cmd === 'io') {
      const field = String(tokens[0] || '').toLowerCase();
      const action = String(tokens[1] || '').toLowerCase();
      const targetMap = {
        hires: dom.toggleHires,
        color: dom.toggleColor,
        sound: dom.toggleSound
      };
      const target = targetMap[field];
      if (!(target instanceof HTMLInputElement)) {
        throw new Error('Usage: io <hires|color|sound> <on|off|toggle>');
      }
      if (action === 'toggle') {
        target.checked = !target.checked;
      } else {
        const parsed = parseBooleanToken(action);
        if (parsed == null) {
          throw new Error('Usage: io <hires|color|sound> <on|off|toggle>');
        }
        target.checked = parsed;
      }
      dispatchBubbledEvent(target, 'change');
      return `${field}=${target.checked ? 'on' : 'off'}`;
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

    if (cmd === 'memory') {
      const sub = String(tokens[0] || '').toLowerCase();
      if (sub === 'view') {
        if (tokens[1]) {
          setUiInputValueById('memoryStart', tokens[1]);
        }
        if (tokens[2]) {
          setUiInputValueById('memoryLength', tokens[2]);
        }
        actions.refreshMemoryView();
        return `memory view start=${dom.memoryStart?.value || ''} len=${dom.memoryLength?.value || ''}`;
      }
      if (sub === 'followpc' || sub === 'follow_pc') {
        const action = String(tokens[1] || '').toLowerCase();
        if (action === 'toggle') {
          actions.setMemoryFollowPcState(!state.memory.followPc);
        } else {
          const parsed = parseBooleanToken(action);
          if (parsed == null) {
            throw new Error('Usage: memory followpc <on|off|toggle>');
          }
          actions.setMemoryFollowPcState(parsed);
        }
        if (dom.memoryFollowPc) {
          dom.memoryFollowPc.checked = state.memory.followPc;
        }
        actions.refreshMemoryView();
        return `memory.followPc=${state.memory.followPc ? 'on' : 'off'}`;
      }
      if (sub === 'write') {
        const addr = tokens[1];
        const value = tokens[2];
        if (!addr || !value) {
          throw new Error('Usage: memory write <addr> <value>');
        }
        setUiInputValueById('memoryWriteAddr', addr);
        setUiInputValueById('memoryWriteValue', value);
        dom.memoryWriteBtn?.click();
        return `memory write requested @${addr}=${value}`;
      }
      if (sub === 'reset') {
        if (tokens[1]) {
          setUiInputValueById('memoryResetVector', tokens[1]);
        }
        await actions.resetApple2WithMemoryVectorOverride();
        return `memory reset vector applied (${dom.memoryResetVector?.value || 'ROM'})`;
      }
      if (sub === 'karateka') {
        await actions.loadKaratekaDump();
        return 'karateka dump load requested';
      }
      if (sub === 'load_last' || sub === 'load-last') {
        await actions.loadLastSavedApple2Dump();
        return 'load last dump requested';
      }
      if (sub === 'save_dump' || sub === 'save-dump') {
        await actions.saveApple2MemoryDump();
        return 'save dump requested';
      }
      if (sub === 'save_snapshot' || sub === 'save-snapshot') {
        await actions.saveApple2MemorySnapshot();
        return 'save snapshot requested';
      }
      if (sub === 'load_selected' || sub === 'load-selected') {
        dom.memoryDumpLoadBtn?.click();
        return 'load selected dump requested';
      }
      throw new Error('Usage: memory <view|followpc|write|reset|karateka|load_last|save_dump|save_snapshot|load_selected> ...');
    }

    if (cmd === 'set') {
      const id = tokens.shift();
      if (!id || tokens.length === 0) {
        throw new Error('Usage: set <elementId> <value>');
      }
      return setUiInputValueById(id, tokens.join(' '));
    }

    if (cmd === 'click') {
      const id = tokens[0];
      if (!id) {
        throw new Error('Usage: click <elementId>');
      }
      return clickUiElementById(id);
    }

    throw new Error(`Unknown command: ${cmd}. Use "help".`);
  }

  async function runTerminalCommand(rawLine) {
    const line = String(rawLine || '').trim();
    if (!line) {
      return;
    }
    terminalWriteLine(`$ ${line}`);
    const result = await executeTerminalCommand(line);
    if (result) {
      terminalWriteLine(result);
    }
  }

  async function submitTerminalInput() {
    const line = String(dom.terminalInput?.value || '').trim();
    if (!line) {
      return;
    }
    if (state.terminal.busy) {
      terminalWriteLine('busy: previous command still running');
      return;
    }
    if (line && (state.terminal.history.length === 0 || state.terminal.history[state.terminal.history.length - 1] !== line)) {
      state.terminal.history.push(line);
    }
    state.terminal.historyIndex = state.terminal.history.length;
    if (dom.terminalInput) {
      dom.terminalInput.value = '';
    }
    state.terminal.busy = true;
    try {
      await runTerminalCommand(line);
    } catch (err) {
      terminalWriteLine(`error: ${err.message || err}`);
    } finally {
      state.terminal.busy = false;
      actions.refreshStatus();
    }
  }

  function terminalHistoryNavigate(delta) {
    const history = state.terminal.history;
    if (!dom.terminalInput || history.length === 0) {
      return;
    }
    const maxIndex = history.length;
    let next = state.terminal.historyIndex + delta;
    next = Math.max(0, Math.min(maxIndex, next));
    state.terminal.historyIndex = next;
    if (next >= history.length) {
      dom.terminalInput.value = '';
      return;
    }
    dom.terminalInput.value = history[next];
    requestFrame(() => {
      dom.terminalInput.selectionStart = dom.terminalInput.value.length;
      dom.terminalInput.selectionEnd = dom.terminalInput.value.length;
    });
  }

  return {
    writeLine: terminalWriteLine,
    clear: terminalClear,
    statusText: terminalStatusText,
    helpText: terminalHelpText,
    executeCommand: executeTerminalCommand,
    runCommand: runTerminalCommand,
    submitInput: submitTerminalInput,
    historyNavigate: terminalHistoryNavigate
  };
}
