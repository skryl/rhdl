import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStoreDispatchers,
  createReduxSyncHelpers,
  installReduxGlobals
} from '../../../app/core/state/store_bridge';

test('createStoreDispatchers forwards action dispatchers', () => {
  const dispatched: any[] = [];
  const appStore = {
    dispatch(action: any) {
      dispatched.push(action);
    }
  };
  const storeActions = {
    setBackend: (value: any) => ({ type: 'setBackend', value }),
    setTheme: (value: any) => ({ type: 'setTheme', value }),
    setRunnerPreset: (value: any) => ({ type: 'setRunnerPreset', value }),
    setActiveTab: (value: any) => ({ type: 'setActiveTab', value }),
    setSidebarCollapsed: (value: any) => ({ type: 'setSidebarCollapsed', value }),
    setTerminalOpen: (value: any) => ({ type: 'setTerminalOpen', value }),
    setRunning: (value: any) => ({ type: 'setRunning', value }),
    setCycle: (value: any) => ({ type: 'setCycle', value }),
    setUiCyclesPending: (value: any) => ({ type: 'setUiCyclesPending', value }),
    setMemoryFollowPc: (value: any) => ({ type: 'setMemoryFollowPc', value }),
    setApple2DisplayHires: (value: any) => ({ type: 'setApple2DisplayHires', value }),
    setApple2DisplayColor: (value: any) => ({ type: 'setApple2DisplayColor', value }),
    setApple2SoundEnabled: (value: any) => ({ type: 'setApple2SoundEnabled', value }),
    mutate: (fn: any) => ({ type: 'mutate', fn })
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
  const dispatched: any[] = [];
  const listeners: any[] = [];
  let currentState = { count: 0 };
  const appStore = {
    dispatch(action: any) {
      dispatched.push(action);
      if (action?.type === 'touch') {
        currentState = { count: currentState.count + 1 };
        listeners.forEach((listener) => listener());
      }
    },
    getState() {
      return currentState;
    },
    subscribe(listener: any) {
      listeners.push(listener);
    }
  };
  const storeActions = {
    touch: (payload: any) => ({ type: 'touch', payload })
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

  assert.equal((windowRef as any).storeKey, appStore);
  assert.deepEqual((windowRef as any).stateKey, currentState);
  (windowRef as any).syncKey('manual');
  assert.equal(dispatched.length, 2);
  assert.equal(dispatched[1].payload.reason, 'manual');
});
