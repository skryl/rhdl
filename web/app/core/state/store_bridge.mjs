export function createStoreDispatchers({ appStore, storeActions } = {}) {
  if (!appStore || !storeActions) {
    throw new Error('createStoreDispatchers requires appStore and storeActions');
  }

  return {
    setBackendState(value) {
      appStore.dispatch(storeActions.setBackend(value));
    },
    setThemeState(value) {
      appStore.dispatch(storeActions.setTheme(value));
    },
    setRunnerPresetState(value) {
      appStore.dispatch(storeActions.setRunnerPreset(value));
    },
    setActiveTabState(value) {
      appStore.dispatch(storeActions.setActiveTab(value));
    },
    setSidebarCollapsedState(value) {
      appStore.dispatch(storeActions.setSidebarCollapsed(value));
    },
    setTerminalOpenState(value) {
      appStore.dispatch(storeActions.setTerminalOpen(value));
    },
    setRunningState(value) {
      appStore.dispatch(storeActions.setRunning(value));
    },
    setCycleState(value) {
      appStore.dispatch(storeActions.setCycle(value));
    },
    setUiCyclesPendingState(value) {
      appStore.dispatch(storeActions.setUiCyclesPending(value));
    },
    setMemoryFollowPcState(value) {
      appStore.dispatch(storeActions.setMemoryFollowPc(value));
    },
    setApple2DisplayHiresState(value) {
      appStore.dispatch(storeActions.setApple2DisplayHires(value));
    },
    setApple2DisplayColorState(value) {
      appStore.dispatch(storeActions.setApple2DisplayColor(value));
    },
    setApple2SoundEnabledState(value) {
      appStore.dispatch(storeActions.setApple2SoundEnabled(value));
    },
    replaceBreakpointsState(nextBreakpoints) {
      appStore.dispatch(storeActions.mutate((draft) => {
        draft.breakpoints = Array.isArray(nextBreakpoints) ? nextBreakpoints : [];
      }));
    }
  };
}

export function createReduxSyncHelpers({ appStore, storeActions } = {}) {
  if (!appStore || !storeActions) {
    throw new Error('createReduxSyncHelpers requires appStore and storeActions');
  }

  let reduxUxSyncPending = false;

  function syncReduxUxState(reason = 'sync') {
    appStore.dispatch(storeActions.touch({ reason, ts: Date.now() }));
  }

  function scheduleReduxUxSync(reason = 'async') {
    if (reduxUxSyncPending) {
      return;
    }
    reduxUxSyncPending = true;
    Promise.resolve().then(() => {
      reduxUxSyncPending = false;
      syncReduxUxState(reason);
    });
  }

  return {
    syncReduxUxState,
    scheduleReduxUxSync
  };
}

export function installReduxGlobals({
  windowRef = globalThis.window,
  appStore,
  syncReduxUxState,
  storeKey,
  stateKey,
  syncKey
} = {}) {
  if (!windowRef || !appStore || typeof syncReduxUxState !== 'function') {
    return;
  }

  try {
    windowRef[storeKey] = appStore;
    windowRef[stateKey] = appStore.getState();
    appStore.subscribe(() => {
      windowRef[stateKey] = appStore.getState();
    });
    windowRef[syncKey] = (reason = 'manual') => syncReduxUxState(reason);
  } catch (_err) {
    // Ignore global assignment failures in constrained environments.
  }
}
