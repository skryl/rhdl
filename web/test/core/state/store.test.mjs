import test from 'node:test';
import assert from 'node:assert/strict';

import { actions } from '../../../app/core/state/actions.mjs';
import { createAppStore } from '../../../app/core/state/store.mjs';

function createInitialState() {
  return {
    backend: 'compiler',
    theme: 'shenzhen',
    runnerPreset: 'apple2',
    activeTab: 'ioTab',
    sidebarCollapsed: false,
    terminalOpen: false,
    running: false,
    cycle: 0,
    uiCyclesPending: 0,
    memory: {
      followPc: false
    },
    apple2: {
      displayHires: false,
      displayColor: false,
      soundEnabled: false
    },
    watches: new Map(),
    breakpoints: []
  };
}

test('app/ui actions update primary state fields', () => {
  const store = createAppStore(createInitialState());

  store.dispatch(actions.setBackend('jit'));
  store.dispatch(actions.setTheme('original'));
  store.dispatch(actions.setRunnerPreset('cpu'));
  store.dispatch(actions.setActiveTab('memoryTab'));
  store.dispatch(actions.setSidebarCollapsed(true));
  store.dispatch(actions.setTerminalOpen(true));
  store.dispatch(actions.setRunning(true));
  store.dispatch(actions.setCycle(42));
  store.dispatch(actions.setUiCyclesPending(7));
  store.dispatch(actions.setMemoryFollowPc(true));
  store.dispatch(actions.setApple2DisplayHires(true));
  store.dispatch(actions.setApple2DisplayColor(true));
  store.dispatch(actions.setApple2SoundEnabled(true));

  const state = store.getState();
  assert.equal(state.backend, 'jit');
  assert.equal(state.theme, 'original');
  assert.equal(state.runnerPreset, 'cpu');
  assert.equal(state.activeTab, 'memoryTab');
  assert.equal(state.sidebarCollapsed, true);
  assert.equal(state.terminalOpen, true);
  assert.equal(state.running, true);
  assert.equal(state.cycle, 42);
  assert.equal(state.uiCyclesPending, 7);
  assert.equal(state.memory.followPc, true);
  assert.equal(state.apple2.displayHires, true);
  assert.equal(state.apple2.displayColor, true);
  assert.equal(state.apple2.soundEnabled, true);
});

test('watch actions manage watch map deterministically', () => {
  const store = createAppStore(createInitialState());

  store.dispatch(actions.watchSet('pc_debug', { idx: 10, width: 16 }));
  store.dispatch(actions.watchSet('a_debug', { idx: 11, width: 8 }));
  assert.equal(store.getState().watches.size, 2);
  assert.deepEqual(store.getState().watches.get('pc_debug'), { idx: 10, width: 16 });

  store.dispatch(actions.watchRemove('pc_debug'));
  assert.equal(store.getState().watches.has('pc_debug'), false);
  assert.equal(store.getState().watches.size, 1);

  store.dispatch(actions.watchClear());
  assert.equal(store.getState().watches.size, 0);
});

test('breakpoint actions replace by signal name and clear cleanly', () => {
  const store = createAppStore(createInitialState());

  store.dispatch(actions.breakpointAddOrReplace({ name: 'pc_debug', width: 16, value: 0xB82A }));
  store.dispatch(actions.breakpointAddOrReplace({ name: 'a_debug', width: 8, value: 0x10 }));
  store.dispatch(actions.breakpointAddOrReplace({ name: 'pc_debug', width: 16, value: 0xB849 }));

  let state = store.getState();
  assert.equal(state.breakpoints.length, 2);
  assert.equal(
    state.breakpoints.find((entry) => entry.name === 'pc_debug')?.value,
    0xB849
  );

  store.dispatch(actions.breakpointRemove('a_debug'));
  state = store.getState();
  assert.equal(state.breakpoints.length, 1);
  assert.equal(state.breakpoints[0].name, 'pc_debug');

  store.dispatch(actions.breakpointClear());
  assert.equal(store.getState().breakpoints.length, 0);
});

test('touch + mutate actions keep store dispatch-friendly for app-level sync', () => {
  const store = createAppStore(createInitialState());
  let notifyCount = 0;

  store.subscribe(() => {
    notifyCount += 1;
  });

  store.dispatch(actions.touch({ reason: 'test' }));
  store.dispatch(actions.mutate((draft) => {
    draft.cycle = 99;
    draft.running = true;
  }));

  const state = store.getState();
  assert.equal(state.cycle, 99);
  assert.equal(state.running, true);
  assert.ok(notifyCount >= 2);
  assert.deepEqual(state.__lastReduxMeta, { reason: 'test' });
});
