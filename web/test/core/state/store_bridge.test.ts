import test from 'node:test';
import assert from 'node:assert/strict';

import {
  createStoreDispatchers,
  createReduxSyncHelpers,
  installReduxGlobals
} from '../../../app/core/state/store_bridge';
import type { ReduxStoreLike, StoreActionsLike } from '../../../app/types/services';
import type { AppState } from '../../../app/types/state';

interface DispatchedAction {
  type: string;
  [key: string]: unknown;
}

test('createStoreDispatchers forwards action dispatchers', () => {
  const dispatched: DispatchedAction[] = [];
  const appStore = {
    dispatch(action: DispatchedAction) {
      dispatched.push(action);
    }
  };
  const storeActions = {
    setBackend: (value: unknown) => ({ type: 'setBackend', value }),
    setTheme: (value: unknown) => ({ type: 'setTheme', value }),
    setRunnerPreset: (value: unknown) => ({ type: 'setRunnerPreset', value }),
    setActiveTab: (value: unknown) => ({ type: 'setActiveTab', value }),
    setSidebarCollapsed: (value: unknown) => ({ type: 'setSidebarCollapsed', value }),
    setTerminalOpen: (value: unknown) => ({ type: 'setTerminalOpen', value }),
    setRunning: (value: unknown) => ({ type: 'setRunning', value }),
    setCycle: (value: unknown) => ({ type: 'setCycle', value }),
    setUiCyclesPending: (value: unknown) => ({ type: 'setUiCyclesPending', value }),
    setMemoryFollowPc: (value: unknown) => ({ type: 'setMemoryFollowPc', value }),
    setMemoryShowSource: (value: unknown) => ({ type: 'setMemoryShowSource', value }),
    setApple2DisplayHires: (value: unknown) => ({ type: 'setApple2DisplayHires', value }),
    setApple2DisplayColor: (value: unknown) => ({ type: 'setApple2DisplayColor', value }),
    setApple2SoundEnabled: (value: unknown) => ({ type: 'setApple2SoundEnabled', value }),
    mutate: (fn: unknown) => ({ type: 'mutate', fn })
  };

  const dispatchers = createStoreDispatchers({
    appStore: appStore as unknown as ReduxStoreLike<AppState>,
    storeActions: storeActions as unknown as StoreActionsLike
  });
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
  const dispatched: DispatchedAction[] = [];
  const listeners: Array<() => void> = [];
  let currentState = { count: 0 };
  const appStore = {
    dispatch(action: DispatchedAction) {
      dispatched.push(action);
      if (action?.type === 'touch') {
        currentState = { count: currentState.count + 1 };
        listeners.forEach((listener) => listener());
      }
    },
    getState() {
      return currentState;
    },
    subscribe(listener: () => void) {
      listeners.push(listener);
      return () => {};
    }
  };
  const storeActions = {
    touch: (payload: unknown) => ({ type: 'touch', payload })
  };

  const { syncReduxUxState, scheduleReduxUxSync } = createReduxSyncHelpers({
    appStore: appStore as unknown as ReduxStoreLike<AppState>,
    storeActions: storeActions as unknown as StoreActionsLike
  });
  scheduleReduxUxSync('a');
  scheduleReduxUxSync('b');
  await Promise.resolve();

  assert.equal(dispatched.length, 1);
  assert.equal(dispatched[0].type, 'touch');
  assert.equal((dispatched[0].payload as { reason?: string }).reason, 'a');

  const windowRef: Record<string, unknown> = {};
  installReduxGlobals({
    windowRef,
    appStore: appStore as unknown as ReduxStoreLike<AppState>,
    syncReduxUxState,
    storeKey: 'storeKey',
    stateKey: 'stateKey',
    syncKey: 'syncKey'
  });

  const installed = windowRef as {
    storeKey?: typeof appStore;
    stateKey?: typeof currentState;
    syncKey?: (reason?: string) => void;
  };

  assert.equal(installed.storeKey, appStore);
  assert.deepEqual(installed.stateKey, currentState);
  installed.syncKey?.('manual');
  assert.equal(dispatched.length, 2);
  assert.equal((dispatched[1].payload as { reason?: string }).reason, 'manual');
});
