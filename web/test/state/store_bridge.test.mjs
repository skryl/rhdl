import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStoreDispatchers,
  createReduxSyncHelpers,
  installReduxGlobals
} from '../../app/state/store_bridge.mjs';

test('createStoreDispatchers forwards action dispatchers', () => {
  const dispatched = [];
  const appStore = {
    dispatch(action) {
      dispatched.push(action);
    }
  };
  const storeActions = {
    setBackend: (value) => ({ type: 'setBackend', value }),
    setTheme: (value) => ({ type: 'setTheme', value }),
    setRunnerPreset: (value) => ({ type: 'setRunnerPreset', value }),
    setActiveTab: (value) => ({ type: 'setActiveTab', value }),
    setSidebarCollapsed: (value) => ({ type: 'setSidebarCollapsed', value }),
    setTerminalOpen: (value) => ({ type: 'setTerminalOpen', value }),
    setRunning: (value) => ({ type: 'setRunning', value }),
    setCycle: (value) => ({ type: 'setCycle', value }),
    setUiCyclesPending: (value) => ({ type: 'setUiCyclesPending', value }),
    setMemoryFollowPc: (value) => ({ type: 'setMemoryFollowPc', value }),
    setApple2DisplayHires: (value) => ({ type: 'setApple2DisplayHires', value }),
    setApple2DisplayColor: (value) => ({ type: 'setApple2DisplayColor', value }),
    setApple2SoundEnabled: (value) => ({ type: 'setApple2SoundEnabled', value }),
    mutate: (fn) => ({ type: 'mutate', fn })
  };

  const dispatchers = createStoreDispatchers({ appStore, storeActions });
  dispatchers.setBackendState('jit');
  dispatchers.setThemeState('original');
  dispatchers.replaceBreakpointsState([{ signal: 'x', value: 1n }]);

  assert.equal(dispatched[0].type, 'setBackend');
  assert.equal(dispatched[0].value, 'jit');
  assert.equal(dispatched[1].type, 'setTheme');
  assert.equal(dispatched[1].value, 'original');
  assert.equal(dispatched[2].type, 'mutate');
});

test('createReduxSyncHelpers debounces async sync and installReduxGlobals publishes state', async () => {
  const dispatched = [];
  const listeners = [];
  let currentState = { count: 0 };
  const appStore = {
    dispatch(action) {
      dispatched.push(action);
      if (action?.type === 'touch') {
        currentState = { count: currentState.count + 1 };
        listeners.forEach((listener) => listener());
      }
    },
    getState() {
      return currentState;
    },
    subscribe(listener) {
      listeners.push(listener);
    }
  };
  const storeActions = {
    touch: (payload) => ({ type: 'touch', payload })
  };

  const { syncReduxUxState, scheduleReduxUxSync } = createReduxSyncHelpers({ appStore, storeActions });
  scheduleReduxUxSync('a');
  scheduleReduxUxSync('b');
  await Promise.resolve();

  assert.equal(dispatched.length, 1);
  assert.equal(dispatched[0].type, 'touch');
  assert.equal(dispatched[0].payload.reason, 'a');

  const windowRef = {};
  installReduxGlobals({
    windowRef,
    appStore,
    syncReduxUxState,
    storeKey: 'storeKey',
    stateKey: 'stateKey',
    syncKey: 'syncKey'
  });

  assert.equal(windowRef.storeKey, appStore);
  assert.deepEqual(windowRef.stateKey, currentState);
  windowRef.syncKey('manual');
  assert.equal(dispatched.length, 2);
  assert.equal(dispatched[1].payload.reason, 'manual');
});
