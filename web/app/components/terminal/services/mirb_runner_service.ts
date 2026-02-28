const DEFAULT_MIRB_JS_PATH = './assets/pkg/mirb.js';
const DEFAULT_TIMEOUT_MS = 15_000;
const DEFAULT_STDIN_BUFFER_BYTES = 1 << 20;
const DEFAULT_MIRB_WORKER_SCRIPT_PATH = new URL('../workers/mirb_worker.js', import.meta.url).href;

const STDIN_CTRL_WRITE_IDX = 0;
const STDIN_CTRL_READ_IDX = 1;
const STDIN_CTRL_SIGNAL_IDX = 2;
const STDIN_CTRL_CLOSED_IDX = 3;

let sharedWorkerClient: any = null;
let sharedWorkerClientKey = '';

function sanitizeMirbOutput(text: any) {
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

function asError(value: any) {
  if (value instanceof Error) {
    return value;
  }
  return new Error(String(value ?? 'Unknown error'));
}

function resolveScriptUrl(scriptUrl: any, { documentRef, globalRef }: any = {}) {
  const base = documentRef?.baseURI
    || globalRef?.location?.href
    || 'http://localhost/';
  try {
    return new URL(scriptUrl, base).href;
  } catch (_err: any) {
    return String(scriptUrl || DEFAULT_MIRB_JS_PATH);
  }
}

function encodeUtf8(text: any) {
  if (typeof TextEncoder !== 'undefined') {
    return new TextEncoder().encode(String(text ?? ''));
  }
  const source = String(text ?? '');
  const bytes = [];
  for (let i = 0; i < source.length; i += 1) {
    bytes.push(source.charCodeAt(i) & 0xff);
  }
  return Uint8Array.from(bytes);
}

function stripToken(text: any, token: any) {
  return String(text || '').split(String(token || '')).join('');
}

function createCommandToken(requestId: any, nonce: any) {
  return `__RHDL_MIRB_DONE_${requestId}_${Date.now()}_${nonce}__`;
}

function buildCommandSource(source: any, token: any) {
  const code = String(source ?? '').replace(/\r/g, '');
  const encoded = JSON.stringify(code);
  return [
    'begin',
    `__rhdl_result__ = eval(${encoded}, binding, '(rhdl)', 1)`,
    "puts '=> ' + __rhdl_result__.inspect",
    `puts '${token}'`,
    'STDOUT.flush',
    'STDERR.flush',
    'rescue => __rhdl_error__',
    "puts '__RHDL_MIRB_ERROR__:' + __rhdl_error__.message + ' (' + __rhdl_error__.class.to_s + ')'",
    `puts '${token}'`,
    'STDOUT.flush',
    'STDERR.flush',
    'end'
  ].join('; ') + '\n';
}

function normalizeMirbResult(result: any = {}) {
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
  timeoutMs = DEFAULT_TIMEOUT_MS,
  stdinBufferBytes = DEFAULT_STDIN_BUFFER_BYTES
}: any = {}) {
  const WorkerCtor = globalRef?.Worker;
  if (typeof WorkerCtor !== 'function') {
    return null;
  }

  let worker: any = null;
  let initPromise: any = null;
  let initResolve: any = null;
  let initReject: any = null;

  let stdinControl: any = null;
  let stdinData: any = null;

  let nextRequestId = 1;
  let commandNonce = 0;
  let runQueue: Promise<any> = Promise.resolve();
  let activeCommand: any = null;

  const debugIo = globalRef?.__RHDL_MIRB_DEBUG_IO__ === true;

  function hasSharedArrayBufferSupport() {
    return typeof globalRef?.SharedArrayBuffer === 'function'
      && typeof globalRef?.Atomics?.notify === 'function';
  }

  function recordDebugEvent(message: any) {
    if (!debugIo) {
      return;
    }
    const target = globalRef;
    if (!target) {
      return;
    }
    if (!Array.isArray(target.__RHDL_MIRB_DEBUG_LOGS__)) {
      target.__RHDL_MIRB_DEBUG_LOGS__ = [];
    }
    const entry = {
      event: String(message?.event || 'unknown'),
      seq: Number.isFinite(message?.seq) ? message.seq : -1,
      ts: Number.isFinite(message?.ts) ? message.ts : Date.now(),
      details: message
    };
    target.__RHDL_MIRB_DEBUG_LOGS__.push(entry);
    if (target.__RHDL_MIRB_DEBUG_LOGS__.length > 2000) {
      target.__RHDL_MIRB_DEBUG_LOGS__.splice(0, target.__RHDL_MIRB_DEBUG_LOGS__.length - 2000);
    }
  }

  function clearStdinBuffers() {
    stdinControl = null;
    stdinData = null;
  }

  function closeStdinChannel() {
    if (!stdinControl) {
      return;
    }
    try {
      Atomics.store(stdinControl, STDIN_CTRL_CLOSED_IDX, 1);
      Atomics.add(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
      Atomics.notify(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
    } catch (_err: any) {
      // Ignore shared channel close failures.
    }
  }

  function rejectActiveCommand(err: any) {
    if (!activeCommand) {
      return;
    }
    const command = activeCommand;
    activeCommand = null;
    if (command.timeoutId) {
      clearTimeout(command.timeoutId);
    }
    command.reject(asError(err));
  }

  function resolveActiveCommand(result: any) {
    if (!activeCommand) {
      return;
    }
    const command = activeCommand;
    activeCommand = null;
    if (command.timeoutId) {
      clearTimeout(command.timeoutId);
    }
    command.resolve(result);
  }

  function teardownWorker() {
    closeStdinChannel();
    clearStdinBuffers();

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

  function resetWorker(err: any = null) {
    const resetErr = err ? asError(err) : new Error('mirb worker unavailable');
    const pendingInitReject = initReject;
    teardownWorker();
    if (pendingInitReject) {
      pendingInitReject(resetErr);
    }
    rejectActiveCommand(resetErr);
  }

  function configureStdinBuffers(message: any) {
    const controlBuffer = message?.stdinControlBuffer;
    const dataBuffer = message?.stdinDataBuffer;

    if (!(controlBuffer instanceof SharedArrayBuffer) || !(dataBuffer instanceof SharedArrayBuffer)) {
      throw new Error('mirb worker did not provide SharedArrayBuffer stdin channel');
    }

    stdinControl = new Int32Array(controlBuffer);
    stdinData = new Uint8Array(dataBuffer);
    if (stdinData.length < 1024) {
      throw new Error('mirb stdin buffer is unexpectedly small');
    }
  }

  function maybeResolveFromToken() {
    if (!activeCommand) {
      return;
    }
    const hasToken = activeCommand.stdout.includes(activeCommand.token)
      || activeCommand.stderr.includes(activeCommand.token);
    if (!hasToken) {
      return;
    }

    resolveActiveCommand({
      exitCode: 0,
      stdout: stripToken(activeCommand.stdout, activeCommand.token),
      stderr: stripToken(activeCommand.stderr, activeCommand.token)
    });
  }

  function appendStreamChunk(stream: any, chunk: any) {
    if (!activeCommand) {
      return;
    }
    const text = String(chunk || '');
    if (!text) {
      return;
    }
    if (stream === 'stdout') {
      activeCommand.stdout += text;
    } else {
      activeCommand.stderr += text;
    }
    maybeResolveFromToken();
  }

  function handleProcessFailure(message: any) {
    const reason = String(
      message?.message
      || (message?.type === 'process_exit'
        ? `mirb process exited (code ${Number(message?.exitCode ?? 0)})`
        : 'mirb process failed')
    );
    resetWorker(new Error(reason));
  }

  function handleWorkerMessage(event: any) {
    const message = event?.data || {};

    if (message.type === 'debug') {
      recordDebugEvent(message);
      return;
    }

    if (message.type === 'ready') {
      try {
        configureStdinBuffers(message);
      } catch (err: any) {
        resetWorker(err);
        return;
      }
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

    if (message.type === 'stdout') {
      appendStreamChunk('stdout', message.data);
      return;
    }

    if (message.type === 'stderr') {
      appendStreamChunk('stderr', message.data);
      return;
    }

    if (message.type === 'process_error' || message.type === 'process_exit') {
      handleProcessFailure(message);
    }
  }

  function startWorker() {
    if (worker && initPromise) {
      return initPromise;
    }
    if (!hasSharedArrayBufferSupport()) {
      throw new Error('SharedArrayBuffer is unavailable; enable cross-origin isolation (COOP/COEP)');
    }

    worker = new WorkerCtor(absoluteWorkerScriptUrl);
    worker.onmessage = handleWorkerMessage;
    worker.onerror = (event: any) => {
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
      scriptUrl: absoluteScriptUrl,
      debugIo,
      stdinBufferBytes
    });

    return initPromise;
  }

  function delay(ms: any) {
    return new Promise((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  function freeQueueSpace(write: any, read: any, capacity: any) {
    if (read > write) {
      return read - write - 1;
    }
    return capacity - (write - read) - 1;
  }

  async function enqueueInput(text: any) {
    if (!stdinControl || !stdinData) {
      throw new Error('mirb stdin channel is not ready');
    }

    const bytes = encodeUtf8(text);
    if (bytes.length === 0) {
      return;
    }

    const capacity = stdinData.length;
    let offset = 0;

    while (offset < bytes.length) {
      if ((Atomics.load(stdinControl, STDIN_CTRL_CLOSED_IDX) as unknown as number) === 1) {
        throw new Error('mirb stdin channel was closed');
      }

      const write = Atomics.load(stdinControl, STDIN_CTRL_WRITE_IDX) as unknown as number;
      const read = Atomics.load(stdinControl, STDIN_CTRL_READ_IDX) as unknown as number;
      const space = freeQueueSpace(write, read, capacity);
      if (space <= 0) {
        await delay(1);
        continue;
      }

      const chunk = Math.min(space, bytes.length - offset);
      const first = Math.min(chunk, capacity - write);
      stdinData.set(bytes.subarray(offset, offset + first), write);
      offset += first;

      let nextWrite: number = write + first;
      if (nextWrite >= capacity) {
        nextWrite = 0;
      }

      const second = chunk - first;
      if (second > 0) {
        stdinData.set(bytes.subarray(offset, offset + second), nextWrite);
        offset += second;
        nextWrite += second;
      }

      Atomics.store(stdinControl, STDIN_CTRL_WRITE_IDX, nextWrite);
      Atomics.add(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
      Atomics.notify(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
    }
  }

  async function executeInWorker(source: any) {
    const sourceText = String(source ?? '');
    if (!sourceText.trim()) {
      return {
        exitCode: 0,
        stdout: '',
        stderr: ''
      };
    }

    await startWorker();

    if (activeCommand) {
      throw new Error('mirb worker command overlap detected');
    }

    const requestId = nextRequestId;
    nextRequestId += 1;
    commandNonce += 1;

    const token = createCommandToken(requestId, commandNonce);
    const commandSource = buildCommandSource(sourceText, token);

    return new Promise((resolve, reject) => {
      const timeoutId = setTimeout(() => {
        if (!activeCommand || activeCommand.requestId !== requestId) {
          return;
        }
        rejectActiveCommand(new Error('mirb execution timed out'));
        resetWorker(new Error('mirb worker timed out and was restarted'));
      }, timeoutMs);

      activeCommand = {
        requestId,
        token,
        stdout: '',
        stderr: '',
        timeoutId,
        resolve,
        reject
      };

      enqueueInput(commandSource).catch((err) => {
        if (activeCommand && activeCommand.requestId === requestId) {
          rejectActiveCommand(err);
        }
        resetWorker(err);
      });
    });
  }

  function run(source: any) {
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
  timeoutMs,
  stdinBufferBytes
}: any = {}) {
  return `${absoluteScriptUrl}::${absoluteWorkerScriptUrl}::${timeoutMs}::${stdinBufferBytes}`;
}

function getSharedWorkerClient({
  globalRef,
  absoluteScriptUrl,
  absoluteWorkerScriptUrl,
  timeoutMs,
  stdinBufferBytes
}: any = {}) {
  const key = sharedWorkerKey({
    absoluteScriptUrl,
    absoluteWorkerScriptUrl,
    timeoutMs,
    stdinBufferBytes
  });
  if (sharedWorkerClient && sharedWorkerClientKey === key) {
    return sharedWorkerClient;
  }
  sharedWorkerClient = createWorkerClient({
    globalRef,
    absoluteScriptUrl,
    absoluteWorkerScriptUrl,
    timeoutMs,
    stdinBufferBytes
  });
  sharedWorkerClientKey = key;
  return sharedWorkerClient;
}

export function createMirbCommandRunner({
  globalRef = globalThis,
  documentRef = globalThis.document,
  scriptUrl = DEFAULT_MIRB_JS_PATH,
  timeoutMs = DEFAULT_TIMEOUT_MS,
  stdinBufferBytes = DEFAULT_STDIN_BUFFER_BYTES,
  workerScriptUrl = DEFAULT_MIRB_WORKER_SCRIPT_PATH
}: any = {}) {
  const absoluteScriptUrl = resolveScriptUrl(scriptUrl, { documentRef, globalRef });
  const absoluteWorkerScriptUrl = resolveScriptUrl(workerScriptUrl, { documentRef, globalRef });
  const workerClient = getSharedWorkerClient({
    globalRef,
    absoluteScriptUrl,
    absoluteWorkerScriptUrl,
    timeoutMs,
    stdinBufferBytes
  });

  return async function runMirb(source: any) {
    if (!workerClient) {
      throw new Error('mirb worker is unavailable in this environment. SharedArrayBuffer support is required.');
    }

    const sourceText = String(source ?? '');
    const workerResult = await workerClient.run(sourceText);
    return normalizeMirbResult(workerResult);
  };
}
