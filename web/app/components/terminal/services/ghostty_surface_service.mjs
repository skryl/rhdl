const DEFAULT_GHOSTTY_MODULE_PATH = '../../../../assets/pkg/ghostty-web.js';
const DEFAULT_GHOSTTY_WASM_PATH = '../../../../assets/pkg/ghostty-vt.wasm';
const DEFAULT_THEME = Object.freeze({
  background: '#071421',
  foreground: '#b5d3ef',
  cursor: '#dff3ff',
  cursorAccent: '#071421',
  selectionBackground: '#274261',
  selectionForeground: '#b5d3ef'
});

let ghosttyRuntimePromise = null;

function resolveAssetUrl(path, { documentRef, globalRef } = {}) {
  const base = documentRef?.baseURI || globalRef?.location?.href || 'http://localhost/';
  try {
    return new URL(path, base).href;
  } catch (_err) {
    return String(path || '');
  }
}

function formatErrorMessage(err) {
  if (err instanceof Error && err.message) {
    return err.message;
  }
  return String(err ?? 'unknown error');
}

function isTerminalHostElement(hostElement) {
  if (!hostElement) {
    return false;
  }
  if (typeof hostElement.appendChild !== 'function') {
    return false;
  }
  if (typeof hostElement.ownerDocument !== 'object') {
    return false;
  }
  return true;
}

function normalizeCssColor(value, { allowTransparent = false } = {}) {
  if (typeof value !== 'string') {
    return '';
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return '';
  }
  if (!allowTransparent && (trimmed === 'transparent' || trimmed === 'rgba(0, 0, 0, 0)' || trimmed === 'rgba(0,0,0,0)')) {
    return '';
  }
  return trimmed;
}

function firstCssColor(values = [], fallback = '') {
  for (const value of values) {
    const next = normalizeCssColor(value);
    if (next) {
      return next;
    }
  }
  return fallback;
}

function cssVar(style, key) {
  if (!style || typeof style.getPropertyValue !== 'function') {
    return '';
  }
  return String(style.getPropertyValue(key) || '').trim();
}

function resolveTerminalTheme({
  hostElement,
  documentRef = globalThis.document,
  globalRef = globalThis,
  overrides = {}
} = {}) {
  const view = documentRef?.defaultView || globalRef;
  const getComputedStyleFn = typeof view?.getComputedStyle === 'function'
    ? view.getComputedStyle.bind(view)
    : null;
  const hostStyle = getComputedStyleFn ? getComputedStyleFn(hostElement) : null;
  const bodyStyle = getComputedStyleFn && documentRef?.body ? getComputedStyleFn(documentRef.body) : null;

  const background = firstCssColor(
    [
      hostStyle?.backgroundColor,
      cssVar(bodyStyle, '--bg-0')
    ],
    DEFAULT_THEME.background
  );
  const foreground = firstCssColor(
    [
      hostStyle?.color,
      cssVar(bodyStyle, '--text')
    ],
    DEFAULT_THEME.foreground
  );
  const cursor = firstCssColor(
    [
      hostStyle?.caretColor,
      cssVar(bodyStyle, '--accent')
    ],
    DEFAULT_THEME.cursor
  );
  const selectionBackground = firstCssColor(
    [
      cssVar(bodyStyle, '--line'),
      hostStyle?.borderColor
    ],
    DEFAULT_THEME.selectionBackground
  );
  const selectionForeground = firstCssColor(
    [
      foreground
    ],
    DEFAULT_THEME.selectionForeground
  );

  return {
    ...DEFAULT_THEME,
    background,
    foreground,
    cursor,
    cursorAccent: background,
    selectionBackground,
    selectionForeground,
    ...(overrides || {})
  };
}

function normalizeTerminalSnapshotText(text) {
  const normalized = String(text ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  return normalized.replace(/\n/g, '\r\n');
}

function themeSignature(theme) {
  return JSON.stringify(theme || {});
}

async function importGhosttyModule({
  scriptPath = DEFAULT_GHOSTTY_MODULE_PATH,
  fetchImpl = globalThis.fetch,
  documentRef = globalThis.document,
  globalRef = globalThis
} = {}) {
  const moduleUrl = resolveAssetUrl(scriptPath, { documentRef, globalRef });
  if (typeof fetchImpl === 'function') {
    const response = await fetchImpl.call(globalRef, moduleUrl);
    if (!response.ok) {
      throw new Error(`Missing ghostty-web module asset: ${new URL(moduleUrl).pathname}`);
    }
  }
  return import(moduleUrl);
}

async function loadGhosttyRuntimeShared(options = {}) {
  if (!ghosttyRuntimePromise) {
    ghosttyRuntimePromise = (async () => {
      const mod = await importGhosttyModule(options);
      if (typeof mod.Terminal !== 'function') {
        throw new Error('ghostty-web exports are incomplete (missing Terminal).');
      }

      const wasmPath = resolveAssetUrl(
        options.wasmPath || DEFAULT_GHOSTTY_WASM_PATH,
        {
          documentRef: options.documentRef,
          globalRef: options.globalRef
        }
      );
      if (typeof options.fetchImpl === 'function') {
        const response = await options.fetchImpl.call(options.globalRef, wasmPath);
        if (!response.ok) {
          throw new Error(`Missing ghostty wasm asset: ${new URL(wasmPath).pathname}`);
        }
      }

      if (!mod.Ghostty || typeof mod.Ghostty.load !== 'function') {
        if (typeof mod.init !== 'function') {
          throw new Error('ghostty-web exports are incomplete (missing Ghostty/init).');
        }
        await mod.init();
        return { mod, ghostty: null };
      }

      const ghostty = await mod.Ghostty.load(wasmPath);
      return { mod, ghostty };
    })().catch((err) => {
      ghosttyRuntimePromise = null;
      throw err;
    });
  }
  return ghosttyRuntimePromise;
}

function safeSetDataset(hostElement, key, value) {
  if (!hostElement || !hostElement.dataset) {
    return;
  }
  hostElement.dataset[key] = String(value ?? '');
}

export function createGhosttyTerminalSurface({
  hostElement,
  scriptPath = DEFAULT_GHOSTTY_MODULE_PATH,
  wasmPath = DEFAULT_GHOSTTY_WASM_PATH,
  fetchImpl = globalThis.fetch,
  documentRef = globalThis.document,
  globalRef = globalThis,
  options = {}
} = {}) {
  if (!isTerminalHostElement(hostElement)) {
    return null;
  }

  let disposed = false;
  let terminal = null;
  let fitAddon = null;
  let renderedText = '';
  let pendingText = '';
  let themeObserver = null;
  let renderedThemeSignature = '';

  hostElement.classList?.add('ghostty-terminal-host');

  function writeRaw(raw) {
    if (!terminal) {
      return;
    }
    const text = String(raw ?? '');
    if (!text) {
      return;
    }
    terminal.write(text);
  }

  function writeTextChunk(text) {
    if (!terminal) {
      return;
    }
    const normalized = normalizeTerminalSnapshotText(text);
    if (!normalized) {
      return;
    }
    terminal.write(normalized);
  }

  function resetAndWriteSnapshot(snapshot) {
    if (!terminal) {
      return;
    }
    if (typeof terminal.reset === 'function') {
      terminal.reset();
    } else if (typeof terminal.clear === 'function') {
      terminal.clear();
    }
    writeTextChunk(snapshot);
    renderedText = snapshot;
  }

  function tryAppendSnapshot(snapshot) {
    if (!snapshot.startsWith(renderedText)) {
      return false;
    }
    const delta = snapshot.slice(renderedText.length);
    writeTextChunk(delta);
    renderedText = snapshot;
    return true;
  }

  function tryBackspaceSnapshot(snapshot) {
    if (!renderedText.startsWith(snapshot)) {
      return false;
    }
    const removed = renderedText.slice(snapshot.length);
    if (removed.includes('\n') || removed.includes('\r')) {
      return false;
    }
    if (!removed) {
      renderedText = snapshot;
      return true;
    }
    writeRaw('\b \b'.repeat(removed.length));
    renderedText = snapshot;
    return true;
  }

  function tryReplacePromptLine(snapshot) {
    const prevBreak = renderedText.lastIndexOf('\n');
    const nextBreak = snapshot.lastIndexOf('\n');
    const prevHead = prevBreak >= 0 ? renderedText.slice(0, prevBreak + 1) : '';
    const nextHead = nextBreak >= 0 ? snapshot.slice(0, nextBreak + 1) : '';
    if (prevHead !== nextHead) {
      return false;
    }
    const nextPrompt = snapshot.slice(nextBreak + 1);
    // Cursor is always at terminal end in this UI model; rewrite only the editable prompt row.
    writeRaw('\r\x1b[2K\x1b[J');
    writeTextChunk(nextPrompt);
    renderedText = snapshot;
    return true;
  }

  function writeSnapshot(snapshot) {
    if (!terminal) {
      return;
    }
    if (snapshot === renderedText) {
      return;
    }

    if (!renderedText) {
      resetAndWriteSnapshot(snapshot);
      return;
    }

    if (tryAppendSnapshot(snapshot)) {
      return;
    }

    if (tryBackspaceSnapshot(snapshot)) {
      return;
    }

    if (tryReplacePromptLine(snapshot)) {
      return;
    }

    resetAndWriteSnapshot(snapshot);
  }

  function applyTheme(theme) {
    if (!terminal || !terminal.renderer || typeof terminal.renderer.setTheme !== 'function') {
      return;
    }
    const signature = themeSignature(theme);
    if (signature === renderedThemeSignature) {
      return;
    }
    terminal.renderer.setTheme(theme);
    if (terminal.wasmTerm && typeof terminal.renderer.render === 'function') {
      const viewportY = Number.isFinite(terminal.viewportY) ? terminal.viewportY : 0;
      terminal.renderer.render(terminal.wasmTerm, true, viewportY, terminal);
    }
    renderedThemeSignature = signature;
  }

  function handleThemeMutation() {
    const theme = resolveTerminalTheme({
      hostElement,
      documentRef,
      globalRef,
      overrides: options.theme || {}
    });
    applyTheme(theme);
  }

  const readyPromise = loadGhosttyRuntimeShared({
    scriptPath,
    wasmPath,
    fetchImpl,
    documentRef,
    globalRef
  }).then(({ mod, ghostty }) => {
    if (disposed) {
      return;
    }

    const initialTheme = resolveTerminalTheme({
      hostElement,
      documentRef,
      globalRef,
      overrides: options.theme || {}
    });
    const nextTerminal = new mod.Terminal({
      cursorBlink: true,
      cursorStyle: 'block',
      fontSize: 12,
      fontFamily: 'IBM Plex Mono, monospace',
      theme: initialTheme,
      disableStdin: true,
      scrollback: 1200,
      ...(ghostty ? { ghostty } : {})
    });

    nextTerminal.open(hostElement);

    if (typeof mod.FitAddon === 'function') {
      const nextFitAddon = new mod.FitAddon();
      nextTerminal.loadAddon(nextFitAddon);
      if (typeof nextFitAddon.fit === 'function') {
        nextFitAddon.fit();
      }
      if (typeof nextFitAddon.observeResize === 'function') {
        nextFitAddon.observeResize();
      }
      fitAddon = nextFitAddon;
    }

    terminal = nextTerminal;
    renderedThemeSignature = '';
    applyTheme(initialTheme);

    const MutationObserverCtor = globalRef?.MutationObserver;
    if (typeof MutationObserverCtor === 'function' && documentRef?.body) {
      themeObserver = new MutationObserverCtor(() => {
        handleThemeMutation();
      });
      themeObserver.observe(documentRef.body, {
        attributes: true,
        attributeFilter: ['class', 'style']
      });
    }
    safeSetDataset(hostElement, 'terminalRenderer', 'ghostty-web');
    writeSnapshot(pendingText);
  }).catch((err) => {
    const message = formatErrorMessage(err);
    safeSetDataset(hostElement, 'terminalRenderer', 'ghostty-web-error');
    safeSetDataset(hostElement, 'terminalError', message);
    if (globalRef?.console?.warn) {
      globalRef.console.warn(`ghostty-web unavailable; falling back to plain text terminal: ${message}`);
    }
  });

  return {
    setText(text) {
      pendingText = String(text ?? '');
      safeSetDataset(hostElement, 'terminalText', pendingText);
      writeSnapshot(pendingText);
    },
    clear() {
      this.setText('');
    },
    focus() {
      if (terminal && typeof terminal.focus === 'function') {
        terminal.focus();
        return;
      }
      if (typeof hostElement.focus === 'function') {
        hostElement.focus();
      }
    },
    dispose() {
      disposed = true;
      if (themeObserver && typeof themeObserver.disconnect === 'function') {
        themeObserver.disconnect();
      }
      themeObserver = null;
      if (fitAddon && typeof fitAddon.dispose === 'function') {
        fitAddon.dispose();
      }
      fitAddon = null;
      if (terminal && typeof terminal.dispose === 'function') {
        terminal.dispose();
      }
      terminal = null;
      renderedText = '';
      renderedThemeSignature = '';
    },
    whenReady() {
      return readyPromise;
    }
  };
}
