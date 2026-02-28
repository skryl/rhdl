export function createStoreDispatchers({ appStore, storeActions }: any = {}) {
  if (!appStore || !storeActions) {
    throw new Error('createStoreDispatchers requires appStore and storeActions');
  }

  return {
    setBackendState(value: any) {
      appStore.dispatch(storeActions.setBackend(value));
    },
    setThemeState(value: any) {
      appStore.dispatch(storeActions.setTheme(value));
    },
    setRunnerPresetState(value: any) {
      appStore.dispatch(storeActions.setRunnerPreset(value));
    },
    setActiveTabState(value: any) {
      appStore.dispatch(storeActions.setActiveTab(value));
    },
    setSidebarCollapsedState(value: any) {
      appStore.dispatch(storeActions.setSidebarCollapsed(value));
    },
    setTerminalOpenState(value: any) {
      appStore.dispatch(storeActions.setTerminalOpen(value));
    },
    setRunningState(value: any) {
      appStore.dispatch(storeActions.setRunning(value));
    },
    setCycleState(value: any) {
      appStore.dispatch(storeActions.setCycle(value));
    },
    setUiCyclesPendingState(value: any) {
      appStore.dispatch(storeActions.setUiCyclesPending(value));
    },
    setMemoryFollowPcState(value: any) {
      appStore.dispatch(storeActions.setMemoryFollowPc(value));
    },
    setMemoryShowSourceState(value: any) {
      appStore.dispatch(storeActions.setMemoryShowSource(value));
    },
    setApple2DisplayHiresState(value: any) {
      appStore.dispatch(storeActions.setApple2DisplayHires(value));
    },
    setApple2DisplayColorState(value: any) {
      appStore.dispatch(storeActions.setApple2DisplayColor(value));
    },
    setApple2SoundEnabledState(value: any) {
      appStore.dispatch(storeActions.setApple2SoundEnabled(value));
    },
    replaceBreakpointsState(nextBreakpoints: any) {
      appStore.dispatch(storeActions.mutate((draft: any) => {
        draft.breakpoints = Array.isArray(nextBreakpoints) ? nextBreakpoints : [];
      }));
    }
  };
}

export function createReduxSyncHelpers({ appStore, storeActions }: any = {}) {
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
}: any = {}) {
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
  } catch (_err: any) {
    // Ignore global assignment failures in constrained environments.
  }
}
