import { createGhosttyTerminalSurface } from './ghostty_surface_service.mjs';

const MAX_TERMINAL_LINES = 900;
const TERMINAL_PROMPT = '$ ';
const TERMINAL_DEBUG_TEXT_DATA_KEY = 'terminalText';

function normalizeTerminalState(state) {
  if (!state.terminal || typeof state.terminal !== 'object') {
    state.terminal = {};
  }
  if (!Array.isArray(state.terminal.history)) {
    state.terminal.history = [];
  }
  if (!Number.isFinite(state.terminal.historyIndex)) {
    state.terminal.historyIndex = state.terminal.history.length;
  }
  if (!Array.isArray(state.terminal.lines)) {
    state.terminal.lines = [];
  }
  if (typeof state.terminal.inputBuffer !== 'string') {
    state.terminal.inputBuffer = '';
  }
  if (typeof state.terminal.busy !== 'boolean') {
    state.terminal.busy = false;
  }
}

function terminalOutputTarget(dom) {
  return dom?.terminalOutput || null;
}

function setTerminalDebugText(target, text) {
  if (!target || !target.dataset) {
    return;
  }
  target.dataset[TERMINAL_DEBUG_TEXT_DATA_KEY] = String(text ?? '');
}

function terminalDisplayText(state) {
  const lines = Array.isArray(state?.terminal?.lines) ? state.terminal.lines : [];
  const inputBuffer = String(state?.terminal?.inputBuffer || '');
  const body = lines.join('\n');
  const promptLine = `${TERMINAL_PROMPT}${inputBuffer}`;
  return body ? `${body}\n${promptLine}` : promptLine;
}

function setTerminalOutputText(target, text) {
  if (!target) {
    return;
  }
  const next = String(text || '');
  setTerminalDebugText(target, next);
  if (typeof target.value === 'string') {
    target.value = next;
  }
  if ('textContent' in target) {
    target.textContent = next;
  }
}

function focusTerminalOutputEnd(target, terminalView = null) {
  if (terminalView && typeof terminalView.focus === 'function') {
    terminalView.focus();
    return;
  }
  if (!target || typeof target.focus !== 'function') {
    return;
  }
  target.focus();
  const text = String(target.value ?? target.textContent ?? '');
  const end = text.length;
  if (typeof target.setSelectionRange === 'function') {
    target.setSelectionRange(end, end);
    return;
  }
  if ('selectionStart' in target && 'selectionEnd' in target) {
    try {
      target.selectionStart = end;
      target.selectionEnd = end;
    } catch (_err) {
      // Ignore cursor placement failures for non-text input mocks.
    }
  }
}

function syncLegacyInput(dom, state) {
  if (!dom?.terminalInput || dom.terminalInput === dom.terminalOutput) {
    return;
  }
  if (typeof dom.terminalInput.value === 'string') {
    dom.terminalInput.value = state.terminal.inputBuffer;
  }
}

function renderTerminal(dom, state, terminalView, requestFrame, { focus = false } = {}) {
  const target = terminalOutputTarget(dom);
  if (!target && !terminalView) {
    return;
  }
  const text = terminalDisplayText(state);
  if (terminalView && typeof terminalView.setText === 'function') {
    terminalView.setText(text);
    setTerminalDebugText(target, text);
  } else if (target) {
    setTerminalOutputText(target, text);
    target.scrollTop = target.scrollHeight;
  }
  syncLegacyInput(dom, state);
  if (focus) {
    requestFrame(() => {
      focusTerminalOutputEnd(target, terminalView);
    });
  }
}

function appendTerminalLine(state, message, maxLines = MAX_TERMINAL_LINES) {
  const text = String(message ?? '');
  const nextLines = text.split('\n');
  state.terminal.lines.push(...nextLines);
  if (state.terminal.lines.length > maxLines) {
    state.terminal.lines = state.terminal.lines.slice(state.terminal.lines.length - maxLines);
  }
}

function clearTerminalOutput(state) {
  state.terminal.lines = [];
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
  terminalView = null,
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

  normalizeTerminalState(state);
  const outputTarget = terminalOutputTarget(dom);
  const resolvedTerminalView = terminalView
    || createGhosttyTerminalSurface({ hostElement: outputTarget })
    || null;
  renderTerminal(dom, state, resolvedTerminalView, requestFrame);

  async function submitInput() {
    const fallback = String(dom?.terminalInput?.value || '');
    const raw = String(state.terminal.inputBuffer || fallback);
    const line = raw.trim();
    if (!line) {
      renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
      return;
    }
    if (state.terminal.busy) {
      appendTerminalLine(state, 'busy: previous command still running');
      renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
      return;
    }

    updateTerminalHistory(state, line);
    state.terminal.inputBuffer = '';
    renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
    state.terminal.busy = true;
    try {
      await runCommand(line);
    } catch (err) {
      appendTerminalLine(state, `error: ${err.message || err}`);
    } finally {
      state.terminal.busy = false;
      refreshStatus();
      renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
    }
  }

  function historyNavigate(delta) {
    const history = state.terminal.history;
    if (history.length === 0) {
      return;
    }
    const maxIndex = history.length;
    let next = state.terminal.historyIndex + delta;
    next = Math.max(0, Math.min(maxIndex, next));
    state.terminal.historyIndex = next;
    if (next >= history.length) {
      state.terminal.inputBuffer = '';
      renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
      return;
    }
    state.terminal.inputBuffer = String(history[next] || '');
    renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
  }

  function appendInput(text) {
    const chunk = String(text || '').replace(/\r/g, '').replace(/\n/g, ' ');
    if (!chunk) {
      return;
    }
    state.terminal.inputBuffer += chunk;
    renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
  }

  function backspaceInput() {
    if (!state.terminal.inputBuffer) {
      renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
      return;
    }
    state.terminal.inputBuffer = state.terminal.inputBuffer.slice(0, -1);
    renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
  }

  function setInput(text = '') {
    state.terminal.inputBuffer = String(text || '');
    renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
  }

  function focusInput() {
    renderTerminal(dom, state, resolvedTerminalView, requestFrame, { focus: true });
  }

  return {
    writeLine: (message = '') => {
      appendTerminalLine(state, message);
      renderTerminal(dom, state, resolvedTerminalView, requestFrame);
    },
    clear: () => {
      clearTerminalOutput(state);
      renderTerminal(dom, state, resolvedTerminalView, requestFrame);
    },
    submitInput,
    historyNavigate,
    appendInput,
    backspaceInput,
    setInput,
    focusInput,
    dispose: () => {
      if (resolvedTerminalView && typeof resolvedTerminalView.dispose === 'function') {
        resolvedTerminalView.dispose();
      }
    }
  };
}
