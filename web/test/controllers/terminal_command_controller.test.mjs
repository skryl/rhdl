import test from 'node:test';
import assert from 'node:assert/strict';

import {
  parseTabToken,
  parseRunnerToken,
  parseBackendToken,
  terminalHelpText,
  createTerminalCommandController
} from '../../app/controllers/terminal_command_controller.mjs';

function makeBaseState() {
  return {
    backend: 'compiler',
    activeTab: 'ioTab',
    running: false,
    cycle: 42,
    watches: new Map([['sig_a', 1n]]),
    breakpoints: [{ name: 'bp_a', width: 1, value: 1n }],
    memory: { followPc: false },
    terminal: {
      history: [],
      historyIndex: 0,
      busy: false
    }
  };
}

function makeBaseDom() {
  return {
    terminalOutput: {
      textContent: '',
      scrollTop: 0,
      scrollHeight: 0
    },
    terminalInput: {
      value: '',
      selectionStart: 0,
      selectionEnd: 0
    },
    tabPanels: [{ id: 'ioTab' }, { id: 'vcdTab' }, { id: 'memoryTab' }],
    runnerSelect: null,
    sampleSelect: null,
    resetBtn: null,
    runBtn: null,
    pauseBtn: null,
    clockSignal: null,
    traceStartBtn: null,
    traceStopBtn: null,
    traceClearBtn: null,
    downloadVcdBtn: null,
    toggleHires: null,
    toggleColor: null,
    toggleSound: null,
    memoryStart: { value: '' },
    memoryLength: { value: '' },
    memoryFollowPc: null,
    memoryWriteBtn: null,
    memoryDumpLoadBtn: null,
    memoryResetVector: { value: '' },
    backendSelect: null
  };
}

function makeBaseActions(state) {
  return {
    currentRunnerPreset: () => ({ id: 'apple2', usesManualIr: false }),
    getBackendDef: () => ({ id: state.backend }),
    setSidebarCollapsed: () => {},
    setTerminalOpen: () => {},
    setActiveTab: () => {},
    setRunnerPresetState: () => {},
    updateIrSourceVisibility: () => {},
    loadRunnerPreset: async () => {},
    refreshStatus: () => {},
    applyTheme: () => {},
    loadSample: async () => {},
    initializeSimulator: async () => {},
    stepSimulation: () => {},
    addWatchSignal: () => true,
    removeWatchSignal: () => true,
    clearAllWatches: () => {
      state.watches.clear();
    },
    addBreakpointSignal: () => 1n,
    clearAllBreakpoints: () => {
      state.breakpoints = [];
    },
    replaceBreakpointsState: (nextBreakpoints) => {
      state.breakpoints = nextBreakpoints;
    },
    renderBreakpointList: () => {},
    setMemoryFollowPcState: () => {},
    refreshMemoryView: () => {},
    resetApple2WithMemoryVectorOverride: async () => {},
    loadKaratekaDump: async () => {},
    loadLastSavedApple2Dump: async () => {},
    saveApple2MemoryDump: async () => {},
    saveApple2MemorySnapshot: async () => {},
    queueApple2Key: () => {},
    formatValue: (value) => String(value)
  };
}

function createControllerHarness() {
  const state = makeBaseState();
  const dom = makeBaseDom();
  const runtime = {
    sim: {
      trace_enabled: () => false
    }
  };
  const backendDefs = {
    compiler: { id: 'compiler' },
    interpreter: { id: 'interpreter' }
  };
  const runnerPresets = {
    apple2: { id: 'apple2' },
    generic: { id: 'generic' }
  };
  const actions = makeBaseActions(state);
  const controller = createTerminalCommandController({
    dom,
    state,
    runtime,
    backendDefs,
    runnerPresets,
    actions,
    requestFrame: (cb) => cb(),
    documentRef: {
      getElementById: () => null
    }
  });
  return { controller, dom, state };
}

test('terminal parser helpers resolve known aliases', () => {
  assert.equal(parseTabToken('memory', [{ id: 'memoryTab' }]), 'memoryTab');
  assert.equal(parseTabToken('customTab', [{ id: 'customTab' }]), 'customTab');
  assert.equal(parseRunnerToken('apple', { apple2: { id: 'apple2' } }), 'apple2');
  assert.equal(parseBackendToken('compiler', { compiler: { id: 'compiler' } }), 'compiler');
});

test('terminalHelpText includes command list', () => {
  const help = terminalHelpText();
  assert.match(help, /Commands:/);
  assert.match(help, /memory reset \[vector\]/);
});

test('submitInput executes status and appends output', async () => {
  const { controller, dom, state } = createControllerHarness();
  dom.terminalInput.value = 'status';
  await controller.submitInput();

  assert.equal(state.terminal.busy, false);
  assert.deepEqual(state.terminal.history, ['status']);
  assert.match(dom.terminalOutput.textContent, /\$ status/);
  assert.match(dom.terminalOutput.textContent, /runner=apple2/);
  assert.match(dom.terminalOutput.textContent, /backend=compiler/);
});

test('submitInput reports unknown commands as errors', async () => {
  const { controller, dom } = createControllerHarness();
  dom.terminalInput.value = 'not_a_real_command';
  await controller.submitInput();
  assert.match(dom.terminalOutput.textContent, /error: Unknown command: not_a_real_command/);
});

test('submitInput prints busy when another command is running', async () => {
  const { controller, dom, state } = createControllerHarness();
  state.terminal.busy = true;
  dom.terminalInput.value = 'status';
  await controller.submitInput();
  assert.match(dom.terminalOutput.textContent, /busy: previous command still running/);
});
