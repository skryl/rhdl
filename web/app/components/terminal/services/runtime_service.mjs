import {
  parseTabToken,
  parseRunnerToken,
  parseBackendToken,
  terminalHelpText
} from '../controllers/helpers/parse.mjs';
import { createTerminalUiHelpers } from '../controllers/helpers/ui.mjs';
import { createTerminalCommandDispatcher } from '../controllers/dispatcher.mjs';
import { createTerminalSessionService } from './session_service.mjs';
import { handleShellRunnerCommand } from '../controllers/commands/shell_runner.mjs';
import { handleSimWatchCommand } from '../controllers/commands/sim_watch.mjs';
import { handleApple2MemoryCommand } from '../controllers/commands/apple2_memory.mjs';
import { handleUiCommand } from '../controllers/commands/ui.mjs';
import { handleIrbCommand } from '../controllers/commands/irb.mjs';
import { createMirbCommandRunner } from './mirb_runner_service.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createTerminalRuntimeService requires function: ${name}`);
  }
}

function createStatusText({ state, runtime, actions }) {
  const runner = actions.currentRunnerPreset();
  const backend = actions.getBackendDef(state.backend);
  const tab = state.activeTab || '-';
  const sim = runtime.sim ? 'ready' : 'not-initialized';
  const trace = runtime.sim ? (runtime.sim.trace_enabled() ? 'on' : 'off') : 'n/a';
  return [
    `runner=${runner.id}`,
    `backend=${backend.id}`,
    `tab=${tab}`,
    `sim=${sim}`,
    `running=${state.running ? 'yes' : 'no'}`,
    `cycle=${state.cycle}`,
    `trace=${trace}`,
    `watches=${state.watches.size}`,
    `breakpoints=${state.breakpoints.length}`
  ].join(' ');
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

export function createTerminalRuntimeService({
  dom,
  state,
  runtime,
  backendDefs,
  runnerPresets,
  actions = {},
  mirbRunner,
  documentRef = globalThis.document,
  eventCtor = globalThis.Event,
  requestFrame = globalThis.requestAnimationFrame || ((cb) => setTimeout(cb, 0))
} = {}) {
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
  const mirbSession = {
    active: false,
    lines: [],
    stdout: '',
    stderr: ''
  };

  function isMirbSessionActive() {
    return mirbSession.active;
  }

  function startMirbSession() {
    if (mirbSession.active) {
      return false;
    }
    mirbSession.active = true;
    mirbSession.lines = [];
    mirbSession.stdout = '';
    mirbSession.stderr = '';
    return true;
  }

  function stopMirbSession() {
    const wasActive = mirbSession.active;
    mirbSession.active = false;
    mirbSession.lines = [];
    mirbSession.stdout = '';
    mirbSession.stderr = '';
    return wasActive;
  }

  async function runMirbSessionLine(line) {
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
    const source = mirbSession.lines.join('\n');
    const result = await runMirb(source);
    const stdout = normalizedText(result?.stdout);
    const stderr = normalizedText(result?.stderr);
    const exitCode = Number(result?.exitCode || 0);
    const outDelta = subtractPreviousOutput(mirbSession.stdout, stdout);
    const errDelta = subtractPreviousOutput(mirbSession.stderr, stderr);

    mirbSession.stdout = stdout;
    mirbSession.stderr = stderr;

    const chunks = [];
    if (outDelta) {
      chunks.push(outDelta);
    }
    if (errDelta) {
      chunks.push(errDelta);
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
      ({ cmd }) => {
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
      runMirb,
      startMirbSession,
      stopMirbSession,
      isMirbSessionActive,
      terminalClear: () => terminalSession.clear(),
      terminalStatusText
    }
  };

  async function executeTerminalCommand(rawLine) {
    return dispatcher.execute(rawLine, commandContext);
  }

  async function runTerminalCommand(rawLine) {
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

  return {
    writeLine: terminalSession.writeLine,
    clear: terminalSession.clear,
    statusText: terminalStatusText,
    helpText: terminalHelpText,
    executeCommand: executeTerminalCommand,
    runCommand: runTerminalCommand,
    submitInput: terminalSession.submitInput,
    historyNavigate: terminalSession.historyNavigate
  };
}
