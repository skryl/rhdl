const DEFAULT_MIRB_JS_PATH = './assets/pkg/mirb.js';
const DEFAULT_TIMEOUT_MS = 15_000;

function joinUrl(base, suffix) {
  const trimmedBase = String(base || '').replace(/[^/]*$/, '');
  return `${trimmedBase}${suffix}`;
}

function encodeUtf8(text) {
  if (typeof TextEncoder !== 'undefined') {
    return new TextEncoder().encode(text);
  }
  const bytes = [];
  for (let i = 0; i < text.length; i += 1) {
    bytes.push(text.charCodeAt(i) & 0xff);
  }
  return Uint8Array.from(bytes);
}

function decodeUtf8(bytes) {
  if (!bytes || bytes.length === 0) {
    return '';
  }
  if (typeof TextDecoder !== 'undefined') {
    return new TextDecoder().decode(Uint8Array.from(bytes));
  }
  return String.fromCharCode(...bytes);
}

function sanitizeMirbOutput(text) {
  const lines = String(text || '').replace(/\r/g, '').split('\n');
  const cleaned = [];

  for (const line of lines) {
    if (line === 'mirb - Embeddable Interactive Ruby Shell') {
      continue;
    }
    if (line === 'This is free software with ABSOLUTELY NO WARRANTY.') {
      continue;
    }

    const unprompted = line.replace(/^([*>]\s?)/, '');
    if (!unprompted.trim()) {
      continue;
    }
    cleaned.push(unprompted);
  }

  return cleaned.join('\n').trim();
}

function createOutputWriter(target) {
  return (value) => {
    if (typeof value === 'number') {
      target.push(value & 0xff);
      return;
    }

    const text = String(value ?? '');
    const bytes = encodeUtf8(`${text}\n`);
    for (let i = 0; i < bytes.length; i += 1) {
      target.push(bytes[i]);
    }
  };
}

function createInputReader(source) {
  const bytes = encodeUtf8(source);
  let index = 0;
  return () => {
    if (index >= bytes.length) {
      return null;
    }
    const next = bytes[index];
    index += 1;
    return next;
  };
}

function asError(value) {
  if (value instanceof Error) {
    return value;
  }
  return new Error(String(value ?? 'Unknown error'));
}

function requireBrowserDocument(documentRef) {
  if (!documentRef || typeof documentRef.createElement !== 'function') {
    throw new Error('mirb is only available in the browser runtime.');
  }
  if (!documentRef.head && !documentRef.body && !documentRef.documentElement) {
    throw new Error('mirb cannot load script host in this document.');
  }
}

function resolveScriptUrl(scriptUrl, { documentRef, globalRef } = {}) {
  const base = documentRef?.baseURI
    || globalRef?.location?.href
    || 'http://localhost/';
  try {
    return new URL(scriptUrl, base).href;
  } catch (_err) {
    return String(scriptUrl || DEFAULT_MIRB_JS_PATH);
  }
}

function createIsolatedFrame(documentRef) {
  const host = documentRef.body || documentRef.documentElement || documentRef.head;
  if (!host || typeof host.appendChild !== 'function') {
    throw new Error('mirb cannot attach iframe host document');
  }

  const iframe = documentRef.createElement('iframe');
  iframe.setAttribute('aria-hidden', 'true');
  iframe.style.display = 'none';
  iframe.src = 'about:blank';
  host.appendChild(iframe);

  const frameWindow = iframe.contentWindow;
  const frameDocument = frameWindow?.document;
  if (!frameWindow || !frameDocument) {
    iframe.remove();
    throw new Error('mirb iframe initialization failed');
  }

  if (!frameDocument.documentElement) {
    frameDocument.open();
    frameDocument.write('<!doctype html><html><head></head><body></body></html>');
    frameDocument.close();
  }

  return {
    frameWindow,
    frameDocument,
    dispose: () => {
      if (iframe.parentNode) {
        iframe.parentNode.removeChild(iframe);
      }
    }
  };
}

export function createMirbCommandRunner({
  globalRef = globalThis,
  documentRef = globalThis.document,
  scriptUrl = DEFAULT_MIRB_JS_PATH,
  timeoutMs = DEFAULT_TIMEOUT_MS
} = {}) {
  return async function runMirb(source) {
    requireBrowserDocument(documentRef);
    const absoluteScriptUrl = resolveScriptUrl(scriptUrl, { documentRef, globalRef });
    const { frameWindow, frameDocument, dispose } = createIsolatedFrame(documentRef);
    const stdoutBytes = [];
    const stderrBytes = [];
    const stdin = createInputReader(`${String(source ?? '')}\n`);
    const stdout = createOutputWriter(stdoutBytes);
    const stderr = createOutputWriter(stderrBytes);

    return new Promise((resolve, reject) => {
      let settled = false;
      let timeoutId = null;

      const finish = (err, exitCode = 0) => {
        if (settled) {
          return;
        }
        settled = true;
        if (timeoutId) {
          clearTimeout(timeoutId);
          timeoutId = null;
        }
        dispose();
        if (err) {
          reject(asError(err));
          return;
        }
        resolve({
          exitCode: Number.isFinite(exitCode) ? exitCode : 0,
          stdout: sanitizeMirbOutput(decodeUtf8(stdoutBytes)),
          stderr: sanitizeMirbOutput(decodeUtf8(stderrBytes))
        });
      };

      timeoutId = setTimeout(() => {
        finish(new Error('mirb execution timed out'));
      }, timeoutMs);

      frameWindow.Module = {
        noInitialRun: true,
        arguments: [],
        stdin,
        stdout,
        stderr,
        print: stdout,
        printErr: stderr,
        locateFile: (path) => {
          if (String(path || '').endsWith('.wasm')) {
            return joinUrl(absoluteScriptUrl, path);
          }
          return joinUrl(absoluteScriptUrl, path);
        },
        onAbort: (reason) => {
          finish(new Error(`mirb aborted: ${String(reason || 'unknown reason')}`));
        },
        onRuntimeInitialized: () => {
          try {
            if (typeof frameWindow.callMain !== 'function') {
              throw new Error('mirb runtime missing global callMain');
            }
            const code = frameWindow.callMain([]);
            finish(null, code);
          } catch (err) {
            finish(err);
          }
        }
      };

      const scriptEl = frameDocument.createElement('script');
      scriptEl.src = absoluteScriptUrl;
      scriptEl.async = true;
      scriptEl.onerror = () => {
        finish(new Error(`Failed to load ${absoluteScriptUrl}`));
      };
      (frameDocument.head || frameDocument.body || frameDocument.documentElement).appendChild(scriptEl);
    });
  };
}
