function appendTerminalLine(dom, message, maxLines = 900) {
  if (!dom?.terminalOutput) {
    return;
  }
  const text = String(message ?? '');
  dom.terminalOutput.textContent += `${text}\n`;
  const lines = dom.terminalOutput.textContent.split('\n');
  if (lines.length > maxLines) {
    dom.terminalOutput.textContent = `${lines.slice(lines.length - maxLines).join('\n')}\n`;
  }
  dom.terminalOutput.scrollTop = dom.terminalOutput.scrollHeight;
}

function clearTerminalOutput(dom) {
  if (!dom?.terminalOutput) {
    return;
  }
  dom.terminalOutput.textContent = '';
}

function updateTerminalHistory(state, line) {
  if (!line) {
    return;
  }
  if (state.terminal.history.length === 0 || state.terminal.history[state.terminal.history.length - 1] !== line) {
    state.terminal.history.push(line);
  }
  state.terminal.historyIndex = state.terminal.history.length;
}

export function createTerminalSessionService({
  dom,
  state,
  requestFrame = globalThis.requestAnimationFrame || ((cb) => setTimeout(cb, 0)),
  runCommand,
  refreshStatus
} = {}) {
  if (!dom || !state) {
    throw new Error('createTerminalSessionService requires dom/state');
  }
  if (typeof runCommand !== 'function') {
    throw new Error('createTerminalSessionService requires function: runCommand');
  }
  if (typeof refreshStatus !== 'function') {
    throw new Error('createTerminalSessionService requires function: refreshStatus');
  }

  async function submitInput() {
    const line = String(dom.terminalInput?.value || '').trim();
    if (!line) {
      return;
    }
    if (state.terminal.busy) {
      appendTerminalLine(dom, 'busy: previous command still running');
      return;
    }

    updateTerminalHistory(state, line);
    if (dom.terminalInput) {
      dom.terminalInput.value = '';
    }
    state.terminal.busy = true;
    try {
      await runCommand(line);
    } catch (err) {
      appendTerminalLine(dom, `error: ${err.message || err}`);
    } finally {
      state.terminal.busy = false;
      refreshStatus();
    }
  }

  function historyNavigate(delta) {
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
    writeLine: (message = '') => appendTerminalLine(dom, message),
    clear: () => clearTerminalOutput(dom),
    submitInput,
    historyNavigate
  };
}
