import { createListenerGroup } from '../../../core/bindings/listener_group.mjs';
import { formatValue } from '../../../core/lib/numeric_utils.mjs';
import { waveformFontFamily, waveformPalette } from '../../../core/lib/theme_utils.mjs';
import { setupWaveformP5 } from '../../watch/ui/waveform_panel.mjs';
import { createTerminalSessionService } from '../../terminal/services/session_service.mjs';
import { createMirbCommandRunner } from '../../terminal/services/mirb_runner_service.mjs';

const DEFAULT_EDITOR_SOURCE = [
  '# RHDL Editor',
  "puts 'Editor ready'",
  '',
  '# Write Ruby and press Execute.'
].join('\n');

const EDITOR_FILE_PATH = '/workspace/editor.rb';
const MIRB_PRELUDE = "require 'rhdl'";

const EXPORT_TIMEOUT_MS = 3500;

function isTerminalTextEntryKey(event) {
  if (!event || typeof event.key !== 'string') {
    return false;
  }
  if (event.ctrlKey || event.metaKey || event.altKey) {
    return false;
  }
  return event.key.length === 1;
}

function normalizedText(value) {
  return String(value || '').replace(/\r/g, '').trim();
}

function subtractPreviousOutput(previous, current) {
  const prev = normalizedText(previous);
  const next = normalizedText(current);
  if (!prev) {
    return next;
  }
  if (next.startsWith(prev)) {
    return next.slice(prev.length).replace(/^\s+/, '');
  }
  return next;
}

function decodeUtf8(buffer) {
  if (!(buffer instanceof ArrayBuffer)) {
    return '';
  }
  if (typeof TextDecoder !== 'function') {
    return '';
  }
  return new TextDecoder().decode(new Uint8Array(buffer));
}

function collectUniqueSignalNames(runtime) {
  if (!runtime?.sim) {
    return [];
  }
  const inputs = Array.isArray(runtime.sim.input_names?.()) ? runtime.sim.input_names() : [];
  const outputs = Array.isArray(runtime.sim.output_names?.()) ? runtime.sim.output_names() : [];
  const seen = new Set();
  const names = [];
  for (const raw of [...inputs, ...outputs]) {
    const name = String(raw || '').trim();
    if (!name || seen.has(name)) {
      continue;
    }
    seen.add(name);
    names.push(name);
  }
  return names;
}

async function loadVimWasmModule(fetchImpl = globalThis.fetch) {
  const moduleUrl = new URL('../../../../assets/pkg/vimwasm.js', import.meta.url);
  if (typeof fetchImpl === 'function') {
    const response = await fetchImpl(moduleUrl.href);
    if (!response.ok) {
      throw new Error(`Missing vim.wasm module asset: ${moduleUrl.pathname}`);
    }
  }
  return import(moduleUrl.href);
}

function setEditorStatus(dom, message, level = 'info') {
  if (!dom?.editorStatus) {
    return;
  }
  dom.editorStatus.textContent = String(message || '');
  dom.editorStatus.dataset.level = String(level || 'info');
}

function setEditorTraceMeta(dom, message) {
  if (!dom?.editorTraceMeta) {
    return;
  }
  dom.editorTraceMeta.textContent = String(message || '');
}

function toggleEditorFallback(dom, showFallback) {
  if (!dom?.editorFallback || !dom?.editorVimWrap) {
    return;
  }
  dom.editorFallback.hidden = !showFallback;
  dom.editorVimWrap.classList.toggle('is-unavailable', !!showFallback);
}

export function bindEditorBindings({
  dom,
  state,
  runtime,
  sim,
  watch,
  log,
  documentRef = globalThis.document,
  windowRef = globalThis.window,
  requestFrame = globalThis.requestAnimationFrame || ((cb) => setTimeout(cb, 0))
} = {}) {
  if (!dom || !state || !runtime) {
    return () => {};
  }
  if (!dom.editorTab || !dom.editorTerminalOutput || !dom.editorExecuteBtn) {
    return () => {};
  }

  const listeners = createListenerGroup();
  const runMirb = createMirbCommandRunner({ documentRef });
  const eventCtor = windowRef?.Event || globalThis.Event;
  const editorTerminalState = {
    terminal: {
      history: [],
      historyIndex: 0,
      busy: false,
      lines: [],
      inputBuffer: ''
    }
  };
  const mirbSession = {
    ready: false,
    lines: [],
    stdout: '',
    stderr: ''
  };
  const vimState = {
    instance: null,
    sourceCache: '',
    pendingExport: null
  };

  if (dom.editorFallback && !String(dom.editorFallback.value || '').trim()) {
    dom.editorFallback.value = DEFAULT_EDITOR_SOURCE;
  }
  vimState.sourceCache = String(dom.editorFallback?.value || DEFAULT_EDITOR_SOURCE);

  let waveformInstance = null;
  let terminalSession = null;
  let disposed = false;

  function emitResize() {
    if (!windowRef || typeof windowRef.dispatchEvent !== 'function') {
      return;
    }
    if (typeof eventCtor !== 'function') {
      return;
    }
    windowRef.dispatchEvent(new eventCtor('resize'));
  }

  function resetMirbSession() {
    mirbSession.ready = false;
    mirbSession.lines = [];
    mirbSession.stdout = '';
    mirbSession.stderr = '';
  }

  async function ensureMirbSessionReady() {
    if (mirbSession.ready) {
      return;
    }
    const result = await runMirb(MIRB_PRELUDE);
    mirbSession.ready = true;
    mirbSession.stdout = normalizedText(result?.stdout);
    mirbSession.stderr = normalizedText(result?.stderr);
  }

  async function runMirbChunk(sourceChunk) {
    const code = String(sourceChunk || '').replace(/\r/g, '').trim();
    if (!code) {
      return null;
    }
    if (code === 'exit' || code === 'quit') {
      resetMirbSession();
      return 'mirb session closed';
    }

    await ensureMirbSessionReady();
    mirbSession.lines.push(code);
    const source = [MIRB_PRELUDE, ...mirbSession.lines].join('\n');
    const result = await runMirb(source);
    const stdout = normalizedText(result?.stdout);
    const stderr = normalizedText(result?.stderr);
    const exitCode = Number(result?.exitCode || 0);
    const outDelta = subtractPreviousOutput(mirbSession.stdout, stdout);
    const errDelta = subtractPreviousOutput(mirbSession.stderr, stderr);

    mirbSession.stdout = stdout;
    mirbSession.stderr = stderr;

    const lines = [];
    if (outDelta) {
      lines.push(outDelta);
    }
    if (errDelta) {
      lines.push(errDelta);
    }
    if (lines.length === 0 && exitCode !== 0) {
      lines.push(`(mirb exit ${exitCode})`);
    }
    return lines.join('\n');
  }

  function syncEditorWatchesToIo() {
    if (!runtime.sim || !watch) {
      return [];
    }
    const names = collectUniqueSignalNames(runtime);
    const target = new Set(names);
    const existing = state.watches instanceof Map ? Array.from(state.watches.keys()) : [];
    for (const name of existing) {
      if (!target.has(name)) {
        watch.removeSignal?.(name);
      }
    }
    for (const name of names) {
      watch.addSignal?.(name);
    }
    return names;
  }

  function refreshEditorTrace() {
    if (!runtime.sim) {
      return;
    }
    try {
      if (runtime.sim.trace_enabled?.() && typeof runtime.sim.trace_capture === 'function') {
        runtime.sim.trace_capture();
      }
    } catch (_err) {
      // Ignore trace capture failures in unsupported runtimes.
    }
    sim?.drainTrace?.();
    watch?.refreshTable?.();
    emitResize();
  }

  async function syncIoAndTraceFromEditorRun() {
    const names = syncEditorWatchesToIo();
    refreshEditorTrace();
    if (names.length > 0) {
      setEditorTraceMeta(dom, `Tracing ${names.length} IO signals`);
    } else {
      setEditorTraceMeta(dom, 'Initialize simulator to trace IO signals');
    }
  }

  async function runEditorTerminalCommand(rawLine) {
    const line = String(rawLine || '').trim();
    if (!line) {
      return;
    }
    const result = await runMirbChunk(line);
    if (result) {
      terminalSession.writeLine(result);
    }
    await syncIoAndTraceFromEditorRun();
  }

  terminalSession = createTerminalSessionService({
    dom: {
      terminalOutput: dom.editorTerminalOutput,
      terminalInput: dom.editorTerminalOutput
    },
    state: editorTerminalState,
    requestFrame,
    runCommand: runEditorTerminalCommand,
    refreshStatus: () => {
      setEditorStatus(dom, mirbSession.ready ? 'mirb session ready' : 'mirb session idle');
    }
  });

  terminalSession.writeLine('Editor terminal ready. Type Ruby or press Execute.');

  function focusEditorTerminal() {
    terminalSession.focusInput();
  }

  listeners.on(dom.editorTerminalOutput, 'keydown', async (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      await terminalSession.submitInput();
      return;
    }
    if (event.key === 'ArrowUp') {
      event.preventDefault();
      terminalSession.historyNavigate(-1);
      return;
    }
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      terminalSession.historyNavigate(1);
      return;
    }
    if (event.key === 'Backspace') {
      event.preventDefault();
      terminalSession.backspaceInput();
      return;
    }
    if (
      event.key === 'ArrowLeft'
      || event.key === 'ArrowRight'
      || event.key === 'Home'
      || event.key === 'End'
      || event.key === 'PageUp'
      || event.key === 'PageDown'
    ) {
      event.preventDefault();
      terminalSession.focusInput();
      return;
    }
    if (isTerminalTextEntryKey(event)) {
      event.preventDefault();
      terminalSession.appendInput(event.key);
    }
  });

  listeners.on(dom.editorTerminalOutput, 'paste', (event) => {
    const pasted = String(event.clipboardData?.getData('text') || '');
    if (!pasted) {
      return;
    }
    event.preventDefault();
    terminalSession.appendInput(pasted);
  });

  listeners.on(dom.editorTerminalOutput, 'focus', () => {
    focusEditorTerminal();
  });

  listeners.on(dom.editorTerminalOutput, 'mousedown', () => {
    setTimeout(() => {
      focusEditorTerminal();
    }, 0);
  });

  if (dom.editorTraceWrap && typeof globalThis.p5 === 'function') {
    try {
      waveformInstance = setupWaveformP5({
        dom,
        state,
        runtime,
        mountElement: dom.editorTraceWrap,
        runtimeKey: 'editorWaveformP5',
        waveformFontFamily,
        waveformPalette,
        formatValue,
        p5Ctor: globalThis.p5
      });
    } catch (err) {
      log(`Editor trace view unavailable: ${err?.message || err}`);
    }
  }

  function resolveVimExport(fullpath, contents) {
    const source = decodeUtf8(contents);
    if (source) {
      vimState.sourceCache = source;
      if (dom.editorFallback) {
        dom.editorFallback.value = source;
      }
    }
    const pending = vimState.pendingExport;
    if (!pending) {
      return;
    }
    const matches = fullpath === pending.path || String(fullpath || '').endsWith('/editor.rb');
    if (!matches) {
      return;
    }
    vimState.pendingExport = null;
    clearTimeout(pending.timeoutId);
    pending.resolve(source || vimState.sourceCache);
  }

  async function exportVimSource() {
    if (!vimState.instance) {
      return String(dom.editorFallback?.value || vimState.sourceCache || '');
    }
    const exported = await new Promise((resolve) => {
      const timeoutId = setTimeout(() => {
        if (vimState.pendingExport) {
          vimState.pendingExport = null;
        }
        resolve(String(vimState.sourceCache || dom.editorFallback?.value || ''));
      }, EXPORT_TIMEOUT_MS);
      vimState.pendingExport = {
        path: EDITOR_FILE_PATH,
        timeoutId,
        resolve
      };
      vimState.instance.cmdline(`write! ${EDITOR_FILE_PATH}`).catch(() => {
        clearTimeout(timeoutId);
        vimState.pendingExport = null;
        resolve(String(vimState.sourceCache || dom.editorFallback?.value || ''));
      });
    });
    return String(exported || '');
  }

  async function readEditorSource() {
    if (vimState.instance) {
      const source = await exportVimSource();
      if (source) {
        return source;
      }
    }
    return String(dom.editorFallback?.value || vimState.sourceCache || '');
  }

  async function executeEditorSource() {
    const source = String(await readEditorSource()).replace(/\r/g, '').trim();
    if (!source) {
      terminalSession.writeLine('error: editor buffer is empty');
      return;
    }
    if (editorTerminalState.terminal.busy) {
      terminalSession.writeLine('busy: previous command still running');
      return;
    }
    editorTerminalState.terminal.busy = true;
    terminalSession.writeLine('$ irb <editor-buffer>');
    try {
      const result = await runMirbChunk(source);
      if (result) {
        terminalSession.writeLine(result);
      }
    } catch (err) {
      terminalSession.writeLine(`error: ${err?.message || err}`);
    } finally {
      editorTerminalState.terminal.busy = false;
      await syncIoAndTraceFromEditorRun();
      focusEditorTerminal();
    }
  }

  listeners.on(dom.editorExecuteBtn, 'click', () => {
    void executeEditorSource();
  });

  listeners.on(dom.editorTab, 'click', () => {
    requestFrame(() => {
      emitResize();
    });
  });

  (async () => {
    try {
      const mod = await loadVimWasmModule();
      if (disposed) {
        return;
      }
      const compatibilityError = typeof mod.checkBrowserCompatibility === 'function'
        ? mod.checkBrowserCompatibility()
        : null;
      if (compatibilityError) {
        toggleEditorFallback(dom, true);
        setEditorStatus(dom, `vim.wasm unavailable: ${compatibilityError}`, 'warn');
        return;
      }
      if (!dom.editorVimCanvas || !dom.editorVimInput) {
        toggleEditorFallback(dom, true);
        setEditorStatus(dom, 'vim.wasm unavailable: editor canvas/input missing', 'warn');
        return;
      }

      const workerScriptUrl = new URL('../../../../assets/pkg/vim.js', import.meta.url);
      const vim = new mod.VimWasm({
        canvas: dom.editorVimCanvas,
        input: dom.editorVimInput,
        workerScriptPath: workerScriptUrl.href
      });
      vim.onError = (err) => {
        setEditorStatus(dom, `vim.wasm error: ${err?.message || err}`, 'warn');
      };
      vim.onFileExport = (fullpath, contents) => {
        resolveVimExport(fullpath, contents);
      };
      vim.onVimInit = () => {
        setEditorStatus(dom, 'vim.wasm ready', 'ok');
      };
      vim.start({
        dirs: ['/workspace'],
        files: {
          [EDITOR_FILE_PATH]: vimState.sourceCache
        },
        cmdArgs: [EDITOR_FILE_PATH]
      });
      vimState.instance = vim;
      toggleEditorFallback(dom, false);
      setEditorStatus(dom, 'Loading vim.wasm...', 'info');

      listeners.on(dom.editorVimCanvas, 'mousedown', () => {
        vim.focus();
      });
      listeners.on(dom.editorVimInput, 'focus', () => {
        vim.focus();
      });
    } catch (err) {
      toggleEditorFallback(dom, true);
      setEditorStatus(dom, `vim.wasm unavailable: ${err?.message || err}`, 'warn');
      log(`Editor vim.wasm init failed: ${err?.message || err}`);
    }
  })();

  setEditorTraceMeta(dom, 'Initialize simulator to trace IO signals');
  requestFrame(() => {
    focusEditorTerminal();
  });

  return () => {
    disposed = true;
    listeners.dispose();
    if (terminalSession && typeof terminalSession.dispose === 'function') {
      terminalSession.dispose();
    }
    if (vimState.instance && typeof vimState.instance.cmdline === 'function') {
      vimState.instance.cmdline('qall!').catch(() => {});
    }
    if (waveformInstance && typeof waveformInstance.remove === 'function') {
      waveformInstance.remove();
    }
  };
}
