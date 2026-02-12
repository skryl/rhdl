const DEFAULT_GHOSTTY_MODULE_PATH = '../../../../assets/pkg/ghostty-web.js';
const DEFAULT_GHOSTTY_WASM_PATH = '../../../../assets/pkg/ghostty-vt.wasm';
const DEFAULT_THEME = Object.freeze({
  background: '#071421',
  foreground: '#b5d3ef',
  cursor: '#dff3ff'
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

  hostElement.classList?.add('ghostty-terminal-host');

  function writeSnapshot(snapshot) {
    if (!terminal) {
      return;
    }
    if (snapshot === renderedText) {
      return;
    }
    if (typeof terminal.reset === 'function') {
      terminal.reset();
    } else if (typeof terminal.clear === 'function') {
      terminal.clear();
    }
    if (snapshot) {
      terminal.write(snapshot);
    }
    renderedText = snapshot;
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

    const nextTerminal = new mod.Terminal({
      cursorBlink: true,
      cursorStyle: 'block',
      fontSize: 12,
      fontFamily: 'IBM Plex Mono, monospace',
      theme: {
        ...DEFAULT_THEME,
        ...(options.theme || {})
      },
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
      if (fitAddon && typeof fitAddon.dispose === 'function') {
        fitAddon.dispose();
      }
      fitAddon = null;
      if (terminal && typeof terminal.dispose === 'function') {
        terminal.dispose();
      }
      terminal = null;
      renderedText = '';
    },
    whenReady() {
      return readyPromise;
    }
  };
}
