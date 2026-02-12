(function mirbWorkerBootstrap(globalRef) {
  const globalObject = globalRef || self;

  let runtimeScriptUrl = '';
  let runtimeInitPromise = null;
  let runtimeReady = false;
  let runtimeAbortReason = '';

  let processRunning = false;
  let processExited = false;
  let processExitCode = null;
  let processStartPromise = null;

  const stdinQueue = [];
  let stdinWakeUp = null;
  let stdinSleeping = false;

  let activeCommand = null;
  let runQueue = Promise.resolve();
  let commandNonce = 0;

  function asMessage(err) {
    if (err instanceof Error && err.message) {
      return err.message;
    }
    return String(err ?? 'unknown error');
  }

  function asError(err) {
    if (err instanceof Error) {
      return err;
    }
    return new Error(asMessage(err));
  }

  function encodeUtf8(text) {
    if (typeof TextEncoder !== 'undefined') {
      return new TextEncoder().encode(String(text ?? ''));
    }
    const bytes = [];
    const source = String(text ?? '');
    for (let i = 0; i < source.length; i += 1) {
      bytes.push(source.charCodeAt(i) & 0xff);
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

  function appendBytes(target, value) {
    if (typeof value === 'number') {
      target.push(value & 0xff);
      return;
    }

    const bytes = encodeUtf8(`${String(value ?? '')}\n`);
    for (let i = 0; i < bytes.length; i += 1) {
      target.push(bytes[i]);
    }
  }

  function joinUrl(base, suffix) {
    const trimmedBase = String(base || '').replace(/[^/]*$/, '');
    return `${trimmedBase}${suffix}`;
  }

  function getAsyncify() {
    const candidate = globalObject.Asyncify || globalObject.Module?.Asyncify;
    if (candidate && typeof candidate.handleSleep === 'function') {
      return candidate;
    }
    return null;
  }

  function wakeStdinIfWaiting() {
    if (typeof stdinWakeUp !== 'function') {
      return;
    }
    const wakeUp = stdinWakeUp;
    stdinWakeUp = null;

    if (stdinQueue.length > 0) {
      stdinSleeping = false;
      wakeUp(stdinQueue.shift());
      return;
    }
    if (processExited) {
      stdinSleeping = false;
      wakeUp(null);
    }
  }

  function enqueueInput(text) {
    const bytes = encodeUtf8(String(text ?? ''));
    for (let i = 0; i < bytes.length; i += 1) {
      stdinQueue.push(bytes[i]);
    }
    wakeStdinIfWaiting();
  }

  function readStdin() {
    if (stdinQueue.length > 0) {
      return stdinQueue.shift();
    }
    if (processExited) {
      return null;
    }

    const asyncify = getAsyncify();
    if (!asyncify) {
      return null;
    }

    if (stdinSleeping) {
      return 0;
    }

    stdinSleeping = true;
    return asyncify.handleSleep((wakeUp) => {
      stdinWakeUp = (value) => {
        stdinSleeping = false;
        wakeUp(value);
      };
    });
  }

  function stripToken(text, token) {
    return String(text || '').split(token).join('');
  }

  function rejectActiveCommand(err) {
    if (!activeCommand) {
      return;
    }
    const command = activeCommand;
    activeCommand = null;
    command.reject(asError(err));
  }

  function maybeResolveActiveCommand() {
    if (!activeCommand) {
      return;
    }

    const stdoutText = decodeUtf8(activeCommand.stdoutBytes);
    const stderrText = decodeUtf8(activeCommand.stderrBytes);
    const hasToken = stdoutText.includes(activeCommand.token) || stderrText.includes(activeCommand.token);
    if (!hasToken) {
      return;
    }

    const command = activeCommand;
    activeCommand = null;
    command.resolve({
      exitCode: 0,
      stdout: stripToken(stdoutText, command.token),
      stderr: stripToken(stderrText, command.token)
    });
  }

  function writeStdout(value) {
    if (!activeCommand) {
      return;
    }
    appendBytes(activeCommand.stdoutBytes, value);
    maybeResolveActiveCommand();
  }

  function writeStderr(value) {
    if (!activeCommand) {
      return;
    }
    appendBytes(activeCommand.stderrBytes, value);
    maybeResolveActiveCommand();
  }

  function startMirbProcess() {
    if (processRunning || processStartPromise) {
      return;
    }

    const callMain = typeof globalObject.callMain === 'function'
      ? globalObject.callMain
      : globalObject.Module?.callMain;

    if (typeof callMain !== 'function') {
      throw new Error('mirb runtime missing callMain');
    }

    const asyncify = getAsyncify();
    if (!asyncify) {
      throw new Error('mirb runtime missing Asyncify.handleSleep support');
    }

    processRunning = true;
    processExited = false;
    processExitCode = null;
    runtimeAbortReason = '';

    processStartPromise = Promise.resolve()
      .then(() => callMain([]))
      .then((exitValue) => {
        processExitCode = Number.isFinite(exitValue) ? Number(exitValue) : 0;
        processExited = true;
        processRunning = false;
        processStartPromise = null;
        wakeStdinIfWaiting();

        const message = runtimeAbortReason
          || `mirb process exited (code ${processExitCode})`;
        rejectActiveCommand(new Error(message));
      })
      .catch((err) => {
        if (err && Number.isFinite(err.status)) {
          processExitCode = Number(err.status);
        }
        processExited = true;
        processRunning = false;
        processStartPromise = null;
        wakeStdinIfWaiting();

        const message = runtimeAbortReason
          || `mirb process failed: ${asMessage(err)}`;
        rejectActiveCommand(new Error(message));
      });
  }

  async function ensureRuntime(scriptUrl) {
    runtimeScriptUrl = String(scriptUrl || runtimeScriptUrl || '');
    if (!runtimeScriptUrl) {
      throw new Error('mirb worker missing script URL');
    }

    if (runtimeReady) {
      if (!processRunning && !processExited) {
        startMirbProcess();
      }
      return;
    }

    if (!runtimeInitPromise) {
      runtimeInitPromise = new Promise((resolve, reject) => {
        globalObject.Module = {
          noInitialRun: true,
          noExitRuntime: true,
          arguments: [],
          stdin: readStdin,
          stdout: writeStdout,
          stderr: writeStderr,
          print: writeStdout,
          printErr: writeStderr,
          locateFile: (path) => joinUrl(runtimeScriptUrl, path),
          onAbort: (reason) => {
            runtimeAbortReason = `mirb aborted: ${String(reason || 'unknown reason')}`;
          },
          onRuntimeInitialized: () => {
            runtimeReady = true;
            resolve();
          }
        };

        try {
          globalObject.importScripts(runtimeScriptUrl);
        } catch (err) {
          reject(err);
        }
      });
    }

    try {
      await runtimeInitPromise;
    } catch (err) {
      runtimeInitPromise = null;
      throw err;
    }

    if (!processRunning && !processExited) {
      startMirbProcess();
    }
  }

  function createCommandToken(requestId) {
    commandNonce += 1;
    return `__RHDL_MIRB_DONE_${requestId}_${Date.now()}_${commandNonce}__`;
  }

  function buildCommandSource(source, token) {
    const code = String(source ?? '').replace(/\r/g, '');
    return `${code}\nputs '${token}'\n`;
  }

  async function runMirb(source, requestId) {
    const sourceText = String(source ?? '');
    const trimmed = sourceText.trim();
    if (!trimmed) {
      return {
        exitCode: 0,
        stdout: '',
        stderr: ''
      };
    }

    await ensureRuntime(runtimeScriptUrl);
    if (!processRunning && !processExited) {
      startMirbProcess();
    }

    if (processExited) {
      const suffix = Number.isFinite(processExitCode)
        ? ` (code ${processExitCode})`
        : '';
      throw new Error(`mirb process is not running${suffix}`);
    }

    if (activeCommand) {
      throw new Error('mirb worker command overlap detected');
    }

    const token = createCommandToken(requestId);
    const commandSource = buildCommandSource(sourceText, token);

    return new Promise((resolve, reject) => {
      activeCommand = {
        token,
        stdoutBytes: [],
        stderrBytes: [],
        resolve,
        reject
      };
      enqueueInput(commandSource);
    });
  }

  function handleMessage(event) {
    const payload = event?.data || {};
    const type = String(payload.type || '').trim();

    if (type === 'init') {
      runtimeScriptUrl = String(payload.scriptUrl || runtimeScriptUrl || '');
      if (!runtimeScriptUrl) {
        globalObject.postMessage({
          type: 'init_error',
          message: 'mirb worker missing script URL'
        });
        return;
      }
      globalObject.postMessage({ type: 'ready' });
      return;
    }

    if (type !== 'run') {
      return;
    }

    const requestId = Number(payload.id);
    const source = String(payload.source ?? '');
    const task = async () => {
      try {
        const result = await runMirb(source, requestId);
        globalObject.postMessage({
          type: 'result',
          id: requestId,
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr
        });
      } catch (err) {
        globalObject.postMessage({
          type: 'error',
          id: requestId,
          message: asMessage(err)
        });
      }
    };

    runQueue = runQueue.then(task, task);
  }

  globalObject.onmessage = handleMessage;
})(self);
