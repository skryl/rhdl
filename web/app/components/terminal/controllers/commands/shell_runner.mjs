import { parseBooleanToken } from '../../lib/tokens.mjs';

export async function handleShellRunnerCommand({ cmd, tokens, context }) {
  const {
    dom,
    state,
    backendDefs,
    runnerPresets,
    actions,
    helpers
  } = context;

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
      helpers.terminalClear();
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
    const tabId = helpers.parseTabToken(tokens[0], dom.tabPanels);
    if (!tabId) {
      throw new Error('Usage: tab <io|vcd|memory|components|schematic>');
    }
    actions.setActiveTab(tabId);
    return `tab=${tabId}`;
  }

  if (cmd === 'runner') {
    const runnerId = helpers.parseRunnerToken(tokens[0], runnerPresets);
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
    const backendId = helpers.parseBackendToken(tokens[0], backendDefs);
    if (!backendId) {
      throw new Error('Usage: backend <interpreter|jit|compiler>');
    }
    if (dom.backendSelect) {
      dom.backendSelect.value = backendId;
      helpers.dispatchBubbledEvent(dom.backendSelect, 'change');
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

  return undefined;
}
