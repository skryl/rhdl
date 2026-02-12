const DEFAULT_MIRB_JS_PATH = './assets/pkg/mirb.js';
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_MIRB_WORKER_SCRIPT_PATH = new URL('../workers/mirb_worker.js', import.meta.url).href;

let sharedWorkerClient = null;
let sharedWorkerClientKey = '';

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

function asError(value) {
  if (value instanceof Error) {
    return value;
  }
  return new Error(String(value ?? 'Unknown error'));
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

function normalizeMirbResult(result = {}) {
  return {
    exitCode: Number.isFinite(result?.exitCode) ? result.exitCode : 0,
    stdout: sanitizeMirbOutput(result?.stdout),
    stderr: sanitizeMirbOutput(result?.stderr)
  };
}

function createWorkerClient({
  globalRef = globalThis,
  absoluteScriptUrl,
  absoluteWorkerScriptUrl,
  timeoutMs = DEFAULT_TIMEOUT_MS
} = {}) {
  const WorkerCtor = globalRef?.Worker;
  if (typeof WorkerCtor !== 'function') {
    return null;
  }

  let worker = null;
  let initPromise = null;
  let initResolve = null;
  let initReject = null;
  let nextRequestId = 1;
  let runQueue = Promise.resolve();
  const pendingRequests = new Map();

  function teardownWorker() {
    if (!worker) {
      initPromise = null;
      initResolve = null;
      initReject = null;
      return;
    }
    worker.onmessage = null;
    worker.onerror = null;
    worker.onmessageerror = null;
    worker.terminate();
    worker = null;
    initPromise = null;
    initResolve = null;
    initReject = null;
  }

  function rejectPendingRequests(err) {
    const error = asError(err);
    for (const pending of pendingRequests.values()) {
      if (pending.timeoutId) {
        clearTimeout(pending.timeoutId);
      }
      pending.reject(error);
    }
    pendingRequests.clear();
  }

  function resetWorker(err = null) {
    const resetErr = err ? asError(err) : null;
    const pendingInitReject = initReject;
    teardownWorker();
    if (pendingInitReject) {
      pendingInitReject(resetErr || new Error('mirb worker reset'));
    }
    rejectPendingRequests(resetErr || new Error('mirb worker unavailable'));
  }

  function resolvePendingResult(message) {
    const id = Number(message?.id);
    if (!Number.isFinite(id)) {
      return;
    }
    const pending = pendingRequests.get(id);
    if (!pending) {
      return;
    }
    pendingRequests.delete(id);
    if (pending.timeoutId) {
      clearTimeout(pending.timeoutId);
    }

    if (message.type === 'result') {
      pending.resolve({
        exitCode: Number.isFinite(message.exitCode) ? message.exitCode : 0,
        stdout: String(message.stdout || ''),
        stderr: String(message.stderr || '')
      });
      return;
    }

    pending.reject(new Error(String(message.message || 'mirb worker execution failed')));
  }

  function handleWorkerMessage(event) {
    const message = event?.data || {};
    if (message.type === 'ready') {
      if (initResolve) {
        initResolve();
      }
      initPromise = Promise.resolve();
      initResolve = null;
      initReject = null;
      return;
    }
    if (message.type === 'init_error') {
      resetWorker(new Error(String(message.message || 'mirb worker failed to initialize')));
      return;
    }
    if (message.type === 'result' || message.type === 'error') {
      resolvePendingResult(message);
    }
  }

  function startWorker() {
    if (worker && initPromise) {
      return initPromise;
    }

    worker = new WorkerCtor(absoluteWorkerScriptUrl);
    worker.onmessage = handleWorkerMessage;
    worker.onerror = (event) => {
      const message = event?.message || event?.error?.message || 'mirb worker crashed';
      resetWorker(new Error(String(message)));
    };
    worker.onmessageerror = () => {
      resetWorker(new Error('mirb worker message parsing failed'));
    };

    initPromise = new Promise((resolve, reject) => {
      initResolve = resolve;
      initReject = reject;
    });
    worker.postMessage({
      type: 'init',
      scriptUrl: absoluteScriptUrl
    });
    return initPromise;
  }

  async function executeInWorker(source) {
    await startWorker();
    if (!worker) {
      throw new Error('mirb worker is unavailable');
    }

    const requestId = nextRequestId;
    nextRequestId += 1;

    return new Promise((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        const pending = pendingRequests.get(requestId);
        if (!pending) {
          return;
        }
        pendingRequests.delete(requestId);
        pending.reject(new Error('mirb execution timed out'));
        resetWorker(new Error('mirb worker timed out and was restarted'));
      }, timeoutMs);

      pendingRequests.set(requestId, {
        resolve,
        reject,
        timeoutId
      });

      worker.postMessage({
        type: 'run',
        id: requestId,
        source: String(source ?? '')
      });
    });
  }

  function run(source) {
    const sourceText = String(source ?? '');
    const task = () => executeInWorker(sourceText);
    runQueue = runQueue.then(task, task);
    return runQueue;
  }

  return {
    run
  };
}

function sharedWorkerKey({
  absoluteScriptUrl,
  absoluteWorkerScriptUrl,
  timeoutMs
} = {}) {
  return `${absoluteScriptUrl}::${absoluteWorkerScriptUrl}::${timeoutMs}`;
}

function getSharedWorkerClient({
  globalRef,
  absoluteScriptUrl,
  absoluteWorkerScriptUrl,
  timeoutMs
} = {}) {
  const key = sharedWorkerKey({
    absoluteScriptUrl,
    absoluteWorkerScriptUrl,
    timeoutMs
  });
  if (sharedWorkerClient && sharedWorkerClientKey === key) {
    return sharedWorkerClient;
  }
  sharedWorkerClient = createWorkerClient({
    globalRef,
    absoluteScriptUrl,
    absoluteWorkerScriptUrl,
    timeoutMs
  });
  sharedWorkerClientKey = key;
  return sharedWorkerClient;
}

export function createMirbCommandRunner({
  globalRef = globalThis,
  documentRef = globalThis.document,
  scriptUrl = DEFAULT_MIRB_JS_PATH,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  workerScriptUrl = DEFAULT_MIRB_WORKER_SCRIPT_PATH
} = {}) {
  const absoluteScriptUrl = resolveScriptUrl(scriptUrl, { documentRef, globalRef });
  const absoluteWorkerScriptUrl = resolveScriptUrl(workerScriptUrl, { documentRef, globalRef });
  const workerClient = getSharedWorkerClient({
    globalRef,
    absoluteScriptUrl,
    absoluteWorkerScriptUrl,
    timeoutMs
  });

  return async function runMirb(source) {
    if (!workerClient) {
      throw new Error('mirb worker is unavailable in this environment.');
    }

    const sourceText = String(source ?? '');
    const workerResult = await workerClient.run(sourceText);
    return normalizeMirbResult(workerResult);
  };
}
