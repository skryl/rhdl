// @ts-nocheck
import {
  parseTabToken,
  parseRunnerToken,
  parseBackendToken,
  terminalHelpText
} from '../controllers/helpers/parse';
import { createTerminalUiHelpers } from '../controllers/helpers/ui';
import { createTerminalCommandDispatcher } from '../controllers/dispatcher';
import { createTerminalSessionService } from './session_service';
import { handleShellRunnerCommand } from '../controllers/commands/shell_runner';
import { handleSimWatchCommand } from '../controllers/commands/sim_watch';
import { handleApple2MemoryCommand } from '../controllers/commands/apple2_memory';
import { handleUiCommand } from '../controllers/commands/ui';
import { handleIrbCommand } from '../controllers/commands/irb';
import { createMirbCommandRunner } from './mirb_runner_service';
import { renderUartTextGrid } from '../../apple2/lib/uart_text';

function requireFn(name: unknown, fn: unknown) {
  if (typeof fn !== 'function') {
    throw new Error(`createTerminalRuntimeService requires function: ${name}`);
  }
}

function createStatusText({ state, runtime, actions }: unknown) {
  const runner = actions.currentRunnerPreset();
  const backend = actions.getBackendDef(state.backend);
  const tab = state.activeTab || '-';
  const sim = runtime.sim ? 'ready' : 'not-initialized';
  const trace = runtime.sim ? (runtime.sim.trace_enabled() ? 'on' : 'off') : 'n/a';
  return [
    `runner=${runner.id}`,
    `backend=${backend.id}`,
    `terminal_uart=${state?.terminal?.uartPassthrough ? 'on' : 'off'}`,
    `tab=${tab}`,
    `sim=${sim}`,
    `running=${state.running ? 'yes' : 'no'}`,
    `cycle=${state.cycle}`,
    `trace=${trace}`,
    `watches=${state.watches.size}`,
    `breakpoints=${state.breakpoints.length}`
  ].join(' ');
}

function buildMirbSessionReplaySource(lines: unknown[] = []) {
  const encodedLines = lines.map((line: unknown) => JSON.stringify(String(line ?? ''))).join(',');
  return [
    '__rhdl_session_binding__ = binding',
    '__rhdl_session_value__ = nil',
    'begin',
    `  [${encodedLines}].each do |__rhdl_session_line__|`,
    "    __rhdl_session_value__ = eval(__rhdl_session_line__, __rhdl_session_binding__, '(rhdl-session)', 1)",
    '  end',
    '  puts "__RHDL_SESSION_RESULT__:" + __rhdl_session_value__.inspect',
    'rescue => __rhdl_session_error__',
    '  puts "__RHDL_SESSION_ERROR__:" + __rhdl_session_error__.message + " (" + __rhdl_session_error__.class.to_s + ")"',
    'end'
  ].join('\n');
}

function parseCssPixelValue(raw: unknown) {
  const value = Number.parseFloat(String(raw ?? '').trim());
  return Number.isFinite(value) ? value : NaN;
}

function resolveUartViewportRows(outputEl: unknown, fallbackRows: unknown) {
  const fallback = Math.max(1, Number.parseInt(String(fallbackRows), 10) || 24);
  if (!outputEl || typeof outputEl.clientHeight !== 'number') {
    return fallback;
  }
  const hostHeight = Number(outputEl.clientHeight);
  if (!Number.isFinite(hostHeight) || hostHeight <= 0) {
    return fallback;
  }

  const view = outputEl.ownerDocument?.defaultView || globalThis;
  const computed = typeof view?.getComputedStyle === 'function'
    ? view.getComputedStyle(outputEl)
    : null;
  const padTop = parseCssPixelValue(computed?.paddingTop);
  const padBottom = parseCssPixelValue(computed?.paddingBottom);
  const availableHeight = Math.max(
    0,
    hostHeight
      - (Number.isFinite(padTop) ? padTop : 0)
      - (Number.isFinite(padBottom) ? padBottom : 0)
  );

  const lineHeightPx = parseCssPixelValue(computed?.lineHeight);
  const fontSizePx = parseCssPixelValue(computed?.fontSize);
  const lineHeight = Number.isFinite(lineHeightPx) && lineHeightPx > 0
    ? lineHeightPx
    : (Number.isFinite(fontSizePx) && fontSizePx > 0 ? fontSizePx * 1.35 : 16);
  if (!Number.isFinite(lineHeight) || lineHeight <= 0) {
    return fallback;
  }

  const estimatedRows = Math.floor(availableHeight / lineHeight);
  if (!Number.isFinite(estimatedRows) || estimatedRows <= 0) {
    return fallback;
  }
  return estimatedRows;
}

function readUartSnapshotText({ state, runtime, dom }: unknown) {
  const sim = runtime?.sim;
  if (!sim) {
    return 'No UART output yet.';
  }
  if (typeof sim.runner_riscv_uart_tx_bytes !== 'function') {
    return 'No UART output yet.';
  }

  const textConfig = state?.apple2?.ioConfig?.display?.text || {};
  const width = Math.max(1, Number.parseInt(textConfig.width, 10) || 80);
  const height = resolveUartViewportRows(dom?.terminalOutput, textConfig.height);
  const maxBytes = width * height;
  let bytes = null;

  if (typeof sim.runner_riscv_uart_tx_len === 'function') {
    const txLen = Number(sim.runner_riscv_uart_tx_len());
    const txLimit = Number.isFinite(txLen) ? Math.max(0, txLen) : 0;
    const readLen = Math.max(0, Math.min(maxBytes, txLimit));
    if (readLen > 0) {
      const offset = Math.max(0, txLimit - readLen);
      bytes = sim.runner_riscv_uart_tx_bytes(offset, readLen);
    }
  }

  if (!bytes || bytes.length === 0) {
    bytes = sim.runner_riscv_uart_tx_bytes(0, maxBytes);
  }

  if (!bytes || bytes.length === 0) {
    return 'No UART output yet.';
  }
  return renderUartTextGrid(bytes, { width, height, textConfig });
}

export function createTerminalRuntimeService({
  dom,
  state,
  runtime,
  backendDefs,
  runnerPresets,
  actions = {} as unknown,
  mirbRunner,
  documentRef = globalThis.document,
  eventCtor = globalThis.Event,
  requestFrame = globalThis.requestAnimationFrame || ((cb: unknown) => setTimeout(cb, 0))
}: unknown = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createTerminalRuntimeService requires dom, state, and runtime');
  }

  requireFn('actions.currentRunnerPreset', actions.currentRunnerPreset);
  requireFn('actions.getBackendDef', actions.getBackendDef);
  requireFn('actions.setSidebarCollapsed', actions.setSidebarCollapsed);
  requireFn('actions.setTerminalOpen', actions.setTerminalOpen);
  requireFn('actions.setActiveTab', actions.setActiveTab);
  requireFn('actions.setRunnerPresetState', actions.setRunnerPresetState);
  requireFn('actions.updateIrSourceVisibility', actions.updateIrSourceVisibility);
  requireFn('actions.loadRunnerPreset', actions.loadRunnerPreset);
  requireFn('actions.refreshStatus', actions.refreshStatus);
  requireFn('actions.applyTheme', actions.applyTheme);
  requireFn('actions.loadSample', actions.loadSample);
  requireFn('actions.initializeSimulator', actions.initializeSimulator);
  requireFn('actions.stepSimulation', actions.stepSimulation);
  requireFn('actions.addWatchSignal', actions.addWatchSignal);
  requireFn('actions.removeWatchSignal', actions.removeWatchSignal);
  requireFn('actions.clearAllWatches', actions.clearAllWatches);
  requireFn('actions.addBreakpointSignal', actions.addBreakpointSignal);
  requireFn('actions.clearAllBreakpoints', actions.clearAllBreakpoints);
  requireFn('actions.replaceBreakpointsState', actions.replaceBreakpointsState);
  requireFn('actions.renderBreakpointList', actions.renderBreakpointList);
  requireFn('actions.setMemoryFollowPcState', actions.setMemoryFollowPcState);
  requireFn('actions.refreshMemoryView', actions.refreshMemoryView);
  requireFn('actions.resetApple2WithMemoryVectorOverride', actions.resetApple2WithMemoryVectorOverride);
  requireFn('actions.loadKaratekaDump', actions.loadKaratekaDump);
  requireFn('actions.loadLastSavedApple2Dump', actions.loadLastSavedApple2Dump);
  requireFn('actions.saveApple2MemoryDump', actions.saveApple2MemoryDump);
  requireFn('actions.saveApple2MemorySnapshot', actions.saveApple2MemorySnapshot);
  requireFn('actions.queueApple2Key', actions.queueApple2Key);
  requireFn('actions.formatValue', actions.formatValue);

  const runMirb = typeof mirbRunner === 'function'
    ? mirbRunner
    : createMirbCommandRunner({ documentRef });
  const syncMirbTrace = typeof actions.syncIoTraceFromMirb === 'function'
    ? actions.syncIoTraceFromMirb
    : null;
  const mirbSession: { active: boolean; lines: unknown[] } = {
    active: false,
    lines: []
  };

  async function runMirbWithTraceSync(source: unknown) {
    const result = await runMirb(source);
    if (syncMirbTrace) {
      await syncMirbTrace();
    }
    return result;
  }

  function isMirbSessionActive() {
    return mirbSession.active;
  }

  function startMirbSession() {
    if (mirbSession.active) {
      return false;
    }
    mirbSession.active = true;
    mirbSession.lines = [];
    return true;
  }

  function stopMirbSession() {
    const wasActive = mirbSession.active;
    mirbSession.active = false;
    mirbSession.lines = [];
    return wasActive;
  }

  async function runMirbSessionLine(line: unknown) {
    const code = String(line || '').trim();
    if (!code) {
      return null;
    }
    if (!mirbSession.active) {
      throw new Error('mirb session is not active.');
    }
    if (code === 'exit' || code === 'quit') {
      stopMirbSession();
      return 'mirb session closed';
    }

    mirbSession.lines.push(code);
    const replaySource = buildMirbSessionReplaySource(mirbSession.lines);
    const result = await runMirbWithTraceSync(replaySource);
    const stdout = String(result?.stdout || '').trim();
    const stderr = String(result?.stderr || '').trim();
    const exitCode = Number(result?.exitCode || 0);
    const combined = [stdout, stderr].filter(Boolean).join('\n').trim();

    const errorMatch = combined.match(/__RHDL_SESSION_ERROR__:(.+)/);
    if (errorMatch) {
      mirbSession.lines.pop();
      return errorMatch[1].trim();
    }

    const resultMatch = combined.match(/__RHDL_SESSION_RESULT__:(.+)/);
    if (resultMatch) {
      return `=> ${resultMatch[1].trim()}`;
    }

    if (exitCode !== 0 || stderr) {
      mirbSession.lines.pop();
    }

    const chunks = [];
    if (stdout) {
      chunks.push(stdout);
    }
    if (stderr) {
      chunks.push(stderr);
    }
    if (chunks.length === 0 && exitCode !== 0) {
      chunks.push(`(mirb exit ${exitCode})`);
    }
    return chunks.join('\n');
  }

  function terminalStatusText() {
    return createStatusText({ state, runtime, actions });
  }

  const uiHelpers = createTerminalUiHelpers({ documentRef, eventCtor });

  const dispatcher = createTerminalCommandDispatcher({
    handlers: [
      ({ cmd }: unknown) => {
        if (cmd === 'help' || cmd === '?') {
          return terminalHelpText();
        }
        if (cmd === 'status') {
          return terminalStatusText();
        }
        if (cmd === 'clear') {
          terminalSession.clear();
          return null;
        }
        return undefined;
      },
      handleShellRunnerCommand,
      handleSimWatchCommand,
      handleApple2MemoryCommand,
      handleIrbCommand,
      handleUiCommand
    ]
  });

  const commandContext = {
    dom,
    state,
    runtime,
    backendDefs,
    runnerPresets,
    actions,
    helpers: {
      ...uiHelpers,
      parseTabToken,
      parseRunnerToken,
      parseBackendToken,
      runMirb: runMirbWithTraceSync,
      startMirbSession,
      stopMirbSession,
      isMirbSessionActive,
      terminalClear: () => terminalSession.clear(),
      terminalStatusText
    }
  };

  async function executeTerminalCommand(rawLine: unknown) {
    return dispatcher.execute(rawLine, commandContext);
  }

  async function runTerminalCommand(rawLine: unknown) {
    const line = String(rawLine || '').trim();
    if (!line) {
      return;
    }
    terminalSession.writeLine(`$ ${line}`);
    if (mirbSession.active) {
      const sessionResult = await runMirbSessionLine(line);
      if (sessionResult) {
        terminalSession.writeLine(sessionResult);
      }
      return;
    }
    const result = await executeTerminalCommand(line);
    if (result) {
      terminalSession.writeLine(result);
    }
  }

  const terminalSession = createTerminalSessionService({
    dom,
    state,
    requestFrame,
    runCommand: runTerminalCommand,
    refreshStatus: actions.refreshStatus
  });

  function syncUartPassthroughDisplay() {
    if (!state?.terminal?.uartPassthrough) {
      terminalSession.setSnapshotOverride(null);
      return;
    }
    terminalSession.setSnapshotOverride(readUartSnapshotText({ state, runtime, dom }) as unknown);
  }

  return {
    writeLine: terminalSession.writeLine,
    clear: terminalSession.clear,
    statusText: terminalStatusText,
    helpText: terminalHelpText,
    executeCommand: executeTerminalCommand,
    runCommand: runTerminalCommand,
    submitInput: terminalSession.submitInput,
    historyNavigate: terminalSession.historyNavigate,
    appendInput: terminalSession.appendInput,
    backspaceInput: terminalSession.backspaceInput,
    setInput: terminalSession.setInput,
    focusInput: terminalSession.focusInput,
    syncUartPassthroughDisplay
  };
}
