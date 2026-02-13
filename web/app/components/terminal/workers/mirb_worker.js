(function mirbWorkerBootstrap(globalRef) {
  const globalObject = globalRef || self;

  const STDIN_CTRL_WRITE_IDX = 0;
  const STDIN_CTRL_READ_IDX = 1;
  const STDIN_CTRL_SIGNAL_IDX = 2;
  const STDIN_CTRL_CLOSED_IDX = 3;
  const STDIN_CTRL_CAPACITY_IDX = 4;
  const STDIN_CTRL_SLOTS = 5;
  const DEFAULT_STDIN_BUFFER_BYTES = 1 << 20;

  let runtimeScriptUrl = '';
  let runtimeInitPromise = null;
  let runtimeReady = false;
  let runtimeAbortReason = '';

  let processRunning = false;
  let processExited = false;
  let processExitCode = null;
  let processStartPromise = null;
  let processStartedAtMs = 0;

  let stdinControlBuffer = null;
  let stdinDataBuffer = null;
  let stdinControl = null;
  let stdinData = null;
  let stdinReadCount = 0;

  let debugIo = false;
  let debugEventSeq = 0;
  let ttyStdinPatched = false;
  let originalTtyRead = null;
  let originalTtyGetChar = null;

  function asMessage(err) {
    if (err instanceof Error && err.message) {
      if (err.stack) {
        return `${err.message}\n${err.stack}`;
      }
      return err.message;
    }
    return String(err ?? 'unknown error');
  }

  function asByteHex(value) {
    if (!Number.isFinite(value)) {
      return null;
    }
    return `0x${(value & 0xff).toString(16).padStart(2, '0')}`;
  }

  function emitDebug(event, details = {}) {
    if (!debugIo) {
      return;
    }
    const payload = {
      type: 'debug',
      event: String(event || 'unknown'),
      ts: Date.now(),
      seq: (debugEventSeq += 1),
      ...details
    };
    try {
      globalObject.postMessage(payload);
    } catch (_err) {
      // Ignore debug transport failures.
    }
  }

  function joinUrl(base, suffix) {
    const trimmedBase = String(base || '').replace(/[^/]*$/, '');
    return `${trimmedBase}${suffix}`;
  }

  function queueLength() {
    if (!stdinControl || !stdinData) {
      return 0;
    }
    const capacity = Atomics.load(stdinControl, STDIN_CTRL_CAPACITY_IDX) || stdinData.length;
    const write = Atomics.load(stdinControl, STDIN_CTRL_WRITE_IDX);
    const read = Atomics.load(stdinControl, STDIN_CTRL_READ_IDX);
    return write >= read ? write - read : capacity - (read - write);
  }

  function hasSharedArrayBufferSupport() {
    return typeof globalObject.SharedArrayBuffer === 'function'
      && typeof globalObject.Atomics?.wait === 'function';
  }

  function initializeStdinChannel(bufferBytes = DEFAULT_STDIN_BUFFER_BYTES) {
    const capacity = Number.isFinite(bufferBytes) && bufferBytes > 1024
      ? Math.floor(bufferBytes)
      : DEFAULT_STDIN_BUFFER_BYTES;

    stdinControlBuffer = new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * STDIN_CTRL_SLOTS);
    stdinDataBuffer = new SharedArrayBuffer(capacity);
    stdinControl = new Int32Array(stdinControlBuffer);
    stdinData = new Uint8Array(stdinDataBuffer);

    Atomics.store(stdinControl, STDIN_CTRL_WRITE_IDX, 0);
    Atomics.store(stdinControl, STDIN_CTRL_READ_IDX, 0);
    Atomics.store(stdinControl, STDIN_CTRL_SIGNAL_IDX, 0);
    Atomics.store(stdinControl, STDIN_CTRL_CLOSED_IDX, 0);
    Atomics.store(stdinControl, STDIN_CTRL_CAPACITY_IDX, capacity);

    emitDebug('stdin.channel.ready', {
      capacity
    });
  }

  function closeStdinChannel() {
    if (!stdinControl) {
      return;
    }
    Atomics.store(stdinControl, STDIN_CTRL_CLOSED_IDX, 1);
    Atomics.add(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
    Atomics.notify(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
    emitDebug('stdin.channel.closed', {
      queueLength: queueLength(),
      processExitCode
    });
  }

  function readFromStdinChannel() {
    if (!stdinControl || !stdinData) {
      return null;
    }

    const capacity = Atomics.load(stdinControl, STDIN_CTRL_CAPACITY_IDX) || stdinData.length;
    while (true) {
      if (processExited || Atomics.load(stdinControl, STDIN_CTRL_CLOSED_IDX) === 1) {
        return null;
      }

      const read = Atomics.load(stdinControl, STDIN_CTRL_READ_IDX);
      const write = Atomics.load(stdinControl, STDIN_CTRL_WRITE_IDX);
      if (read !== write) {
        const value = stdinData[read];
        const nextRead = read + 1 >= capacity ? 0 : read + 1;
        Atomics.store(stdinControl, STDIN_CTRL_READ_IDX, nextRead);
        Atomics.add(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
        Atomics.notify(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
        return value;
      }

      const observed = Atomics.load(stdinControl, STDIN_CTRL_SIGNAL_IDX);
      emitDebug('stdin.wait', {
        signal: observed,
        queueLength: 0
      });
      Atomics.wait(stdinControl, STDIN_CTRL_SIGNAL_IDX, observed);
    }
  }

  function readFromStdinChannelNonBlocking() {
    if (!stdinControl || !stdinData) {
      return null;
    }
    if (processExited || Atomics.load(stdinControl, STDIN_CTRL_CLOSED_IDX) === 1) {
      return null;
    }

    const capacity = Atomics.load(stdinControl, STDIN_CTRL_CAPACITY_IDX) || stdinData.length;
    const read = Atomics.load(stdinControl, STDIN_CTRL_READ_IDX);
    const write = Atomics.load(stdinControl, STDIN_CTRL_WRITE_IDX);
    if (read === write) {
      return undefined;
    }

    const value = stdinData[read];
    const nextRead = read + 1 >= capacity ? 0 : read + 1;
    Atomics.store(stdinControl, STDIN_CTRL_READ_IDX, nextRead);
    Atomics.add(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
    Atomics.notify(stdinControl, STDIN_CTRL_SIGNAL_IDX, 1);
    return value;
  }

  function readStdin() {
    stdinReadCount += 1;
    const value = readFromStdinChannel();
    if (value === null) {
      emitDebug('stdin.read.eof', {
        readCount: stdinReadCount,
        processExitCode
      });
      return null;
    }
    emitDebug('stdin.read.byte', {
      readCount: stdinReadCount,
      queueLengthAfter: queueLength(),
      byte: value,
      byteHex: asByteHex(value)
    });
    return value;
  }

  function readStdinNonBlocking() {
    const value = readFromStdinChannelNonBlocking();
    if (value === undefined) {
      return undefined;
    }

    stdinReadCount += 1;
    if (value === null) {
      emitDebug('stdin.read.eof', {
        readCount: stdinReadCount,
        processExitCode
      });
      return null;
    }

    emitDebug('stdin.read.byte', {
      readCount: stdinReadCount,
      queueLengthAfter: queueLength(),
      byte: value,
      byteHex: asByteHex(value)
    });
    return value;
  }

  function installSabTtyStdinHooks() {
    if (ttyStdinPatched) {
      return;
    }

    const fs = globalObject.FS || globalObject.Module?.FS;
    const tty = globalObject.TTY;
    if (!fs || !tty || !tty.stream_ops || !tty.default_tty_ops) {
      emitDebug('stdin.tty_patch.skipped', {
        hasFs: !!fs,
        hasTty: !!tty
      });
      return;
    }

    originalTtyRead = tty.stream_ops.read;
    originalTtyGetChar = tty.default_tty_ops.get_char;
    if (typeof originalTtyRead !== 'function' || typeof originalTtyGetChar !== 'function') {
      emitDebug('stdin.tty_patch.skipped', {
        hasRead: typeof originalTtyRead === 'function',
        hasGetChar: typeof originalTtyGetChar === 'function'
      });
      return;
    }

    tty.default_tty_ops.get_char = () => readStdinNonBlocking();
    tty.stream_ops.read = function patchedTtyRead(stream, buffer, offset, length, pos) {
      const path = String(stream?.path || '');
      const isStdinStream = stream?.fd === 0 || path === '/dev/stdin' || path === '/dev/tty';
      if (!isStdinStream) {
        return originalTtyRead.call(this, stream, buffer, offset, length, pos);
      }
      if (!stream?.tty || !stream.tty.ops?.get_char) {
        throw new fs.ErrnoError(60);
      }

      let bytesRead = 0;
      for (let i = 0; i < length; i += 1) {
        let result;
        try {
          result = stream.tty.ops.get_char(stream.tty);
        } catch (_err) {
          throw new fs.ErrnoError(29);
        }

        if (result === undefined) {
          if (bytesRead > 0) {
            break;
          }
          result = readStdin();
        }

        if (result === null || result === undefined) {
          break;
        }

        bytesRead += 1;
        buffer[offset + i] = result;
      }

      if (bytesRead > 0) {
        stream.node.atime = Date.now();
      }
      return bytesRead;
    };

    ttyStdinPatched = true;
    emitDebug('stdin.tty_patch.ready', {});
  }

  function emitStreamChunk(type, value) {
    let chunk = '';
    if (typeof value === 'number') {
      chunk = String.fromCharCode(value & 0xff);
    } else {
      chunk = `${String(value ?? '')}\n`;
    }
    if (!chunk) {
      return;
    }

    emitDebug(`${type}.chunk`, {
      length: chunk.length,
      preview: chunk.slice(0, 80)
    });

    try {
      globalObject.postMessage({
        type,
        data: chunk
      });
    } catch (_err) {
      // Ignore stream transport failures.
    }
  }

  function writeStdout(value) {
    emitStreamChunk('stdout', value);
  }

  function writeStderr(value) {
    emitStreamChunk('stderr', value);
  }

  function notifyProcessFailure(kind, message, exitCode = processExitCode) {
    const type = kind === 'exit' ? 'process_exit' : 'process_error';
    try {
      globalObject.postMessage({
        type,
        exitCode,
        message
      });
    } catch (_err) {
      // Ignore process state transport failures.
    }
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

    processRunning = true;
    processExited = false;
    processExitCode = null;
    runtimeAbortReason = '';
    processStartedAtMs = Date.now();
    emitDebug('process.start', {
      queueLength: queueLength()
    });

    processStartPromise = Promise.resolve()
      .then(() => callMain([]))
      .then((exitValue) => {
        processExitCode = Number.isFinite(exitValue) ? Number(exitValue) : 0;
        processExited = true;
        processRunning = false;
        processStartPromise = null;
        closeStdinChannel();

        const message = runtimeAbortReason
          || `mirb process exited (code ${processExitCode})`;
        emitDebug('process.exit', {
          exitCode: processExitCode,
          elapsedMs: Date.now() - processStartedAtMs,
          reason: message
        });
        notifyProcessFailure('exit', message, processExitCode);
      })
      .catch((err) => {
        if (err && Number.isFinite(err.status)) {
          processExitCode = Number(err.status);
        }
        processExited = true;
        processRunning = false;
        processStartPromise = null;
        closeStdinChannel();

        const message = runtimeAbortReason
          || `mirb process failed: ${asMessage(err)}`;
        emitDebug('process.error', {
          exitCode: processExitCode,
          elapsedMs: Date.now() - processStartedAtMs,
          reason: message
        });
        notifyProcessFailure('error', message, processExitCode);
      });
  }

  function emitFsDiagnostics() {
    const fs = globalObject.FS || globalObject.Module?.FS;
    if (!fs) {
      emitDebug('fs.diag', { available: false });
      return;
    }

    const stdinStream = fs.streams?.[0];
    const stdoutStream = fs.streams?.[1];
    const stderrStream = fs.streams?.[2];
    emitDebug('fs.diag', {
      available: true,
      stdinPath: stdinStream?.path || null,
      stdoutPath: stdoutStream?.path || null,
      stderrPath: stderrStream?.path || null,
      stdinHasTty: !!stdinStream?.tty,
      stdoutHasTty: !!stdoutStream?.tty,
      stderrHasTty: !!stderrStream?.tty,
      stdinRdev: stdinStream?.node?.rdev ?? null,
      stdoutRdev: stdoutStream?.node?.rdev ?? null,
      stderrRdev: stderrStream?.node?.rdev ?? null
    });
  }

  async function ensureRuntime(scriptUrl) {
    runtimeScriptUrl = String(scriptUrl || runtimeScriptUrl || '');
    if (!runtimeScriptUrl) {
      throw new Error('mirb worker missing script URL');
    }

    if (runtimeReady) {
      return;
    }

    if (!runtimeInitPromise) {
      runtimeInitPromise = new Promise((resolve, reject) => {
        globalObject.Module = {
          noInitialRun: true,
          noExitRuntime: true,
          arguments: [],
          // Keep default /dev/tty streams so mirb stays in interactive mode.
          print: writeStdout,
          printErr: writeStderr,
          locateFile: (path) => joinUrl(runtimeScriptUrl, path),
          onAbort: (reason) => {
            runtimeAbortReason = `mirb aborted: ${String(reason || 'unknown reason')}`;
            emitDebug('runtime.abort', {
              reason: runtimeAbortReason
            });
          },
          onRuntimeInitialized: () => {
            runtimeReady = true;
            emitDebug('runtime.ready', {});
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
  }

  async function initializeWorker(payload) {
    runtimeScriptUrl = String(payload?.scriptUrl || runtimeScriptUrl || '');
    debugIo = payload?.debugIo === true;
    const stdinBufferBytes = Number(payload?.stdinBufferBytes || DEFAULT_STDIN_BUFFER_BYTES);

    if (!runtimeScriptUrl) {
      throw new Error('mirb worker missing script URL');
    }
    if (!hasSharedArrayBufferSupport()) {
      throw new Error('SharedArrayBuffer/Atomics.wait unavailable; cross-origin isolation is required');
    }

    emitDebug('worker.init', {
      scriptUrl: runtimeScriptUrl,
      stdinBufferBytes
    });

    await ensureRuntime(runtimeScriptUrl);
    emitFsDiagnostics();
    initializeStdinChannel(stdinBufferBytes);
    installSabTtyStdinHooks();

    globalObject.postMessage({
      type: 'ready',
      stdinControlBuffer,
      stdinDataBuffer,
      stdinCapacity: stdinData.length
    });

    // Start the long-lived mirb process after announcing readiness.
    globalObject.setTimeout(() => {
      try {
        startMirbProcess();
      } catch (err) {
        const message = `mirb process failed to start: ${asMessage(err)}`;
        notifyProcessFailure('error', message, null);
      }
    }, 0);
  }

  function handleMessage(event) {
    const payload = event?.data || {};
    const type = String(payload.type || '').trim();

    if (type === 'init') {
      initializeWorker(payload)
        .catch((err) => {
          globalObject.postMessage({
            type: 'init_error',
            message: asMessage(err)
          });
        });
      return;
    }

    if (type === 'close') {
      closeStdinChannel();
    }
  }

  globalObject.onmessage = handleMessage;
})(self);
