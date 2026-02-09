import test from 'node:test';
import assert from 'node:assert/strict';

import { createTerminalSessionService } from '../../../../app/components/terminal/services/session_service.mjs';

function createHarness() {
  const calls = [];
  const dom = {
    terminalOutput: {
      textContent: '',
      scrollTop: 0,
      scrollHeight: 999
    },
    terminalInput: {
      value: '',
      selectionStart: 0,
      selectionEnd: 0
    }
  };
  const state = {
    terminal: {
      history: [],
      historyIndex: 0,
      busy: false
    }
  };
  const service = createTerminalSessionService({
    dom,
    state,
    requestFrame: (cb) => cb(),
    runCommand: async (line) => {
      calls.push(['run', line]);
    },
    refreshStatus: () => {
      calls.push(['refreshStatus']);
    }
  });
  return { service, dom, state, calls };
}

test('terminal session submitInput stores history and runs command', async () => {
  const { service, dom, state, calls } = createHarness();
  dom.terminalInput.value = 'status';
  await service.submitInput();
  assert.equal(state.terminal.busy, false);
  assert.deepEqual(state.terminal.history, ['status']);
  assert.deepEqual(calls, [['run', 'status'], ['refreshStatus']]);
});

test('terminal session submitInput reports busy and does not run command', async () => {
  const { service, dom, state, calls } = createHarness();
  state.terminal.busy = true;
  dom.terminalInput.value = 'status';
  await service.submitInput();
  assert.equal(calls.length, 0);
  assert.match(dom.terminalOutput.textContent, /busy: previous command still running/);
});

test('terminal session historyNavigate updates input value', () => {
  const { service, dom, state } = createHarness();
  state.terminal.history = ['one', 'two'];
  state.terminal.historyIndex = 2;
  service.historyNavigate(-1);
  assert.equal(dom.terminalInput.value, 'two');
});
