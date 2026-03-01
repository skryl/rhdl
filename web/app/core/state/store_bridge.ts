import type { BreakpointModel } from '../../types/models';
import type { AppState, StoreDispatchers } from '../../types/state';
import type {
  InstallReduxGlobalsOptions,
  ReduxStoreLike,
  ReduxSyncHelpers,
  StoreActionsLike
} from '../../types/services';

interface StoreBridgeDeps {
  appStore?: ReduxStoreLike<AppState>;
  storeActions?: StoreActionsLike;
}

function requireStoreBridgeDeps(
  appStore: ReduxStoreLike<AppState> | undefined,
  storeActions: StoreActionsLike | undefined,
  name: string
) {
  if (!appStore || !storeActions) {
    throw new Error(`${name} requires appStore and storeActions`);
  }
  return { appStore, storeActions };
}

export function createStoreDispatchers({ appStore, storeActions }: StoreBridgeDeps = {}): StoreDispatchers {
  const resolved = requireStoreBridgeDeps(appStore, storeActions, 'createStoreDispatchers');
  const { appStore: resolvedStore, storeActions: resolvedActions } = resolved;

  return {
    setBackendState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setBackend(value));
    },
    setThemeState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setTheme(value));
    },
    setRunnerPresetState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setRunnerPreset(value));
    },
    setActiveTabState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setActiveTab(value));
    },
    setSidebarCollapsedState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setSidebarCollapsed(value));
    },
    setTerminalOpenState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setTerminalOpen(value));
    },
    setRunningState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setRunning(value));
    },
    setCycleState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setCycle(value));
    },
    setUiCyclesPendingState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setUiCyclesPending(value));
    },
    setMemoryFollowPcState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setMemoryFollowPc(value));
    },
    setMemoryShowSourceState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setMemoryShowSource(value));
    },
    setApple2DisplayHiresState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setApple2DisplayHires(value));
    },
    setApple2DisplayColorState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setApple2DisplayColor(value));
    },
    setApple2SoundEnabledState(value: unknown) {
      resolvedStore.dispatch(resolvedActions.setApple2SoundEnabled(value));
    },
    replaceBreakpointsState(nextBreakpoints: unknown) {
      resolvedStore.dispatch(resolvedActions.mutate((draft: AppState) => {
        draft.breakpoints = Array.isArray(nextBreakpoints)
          ? (nextBreakpoints as BreakpointModel[])
          : [];
      }));
    }
  };
}

export function createReduxSyncHelpers({ appStore, storeActions }: StoreBridgeDeps = {}): ReduxSyncHelpers {
  const resolved = requireStoreBridgeDeps(appStore, storeActions, 'createReduxSyncHelpers');
  const { appStore: resolvedStore, storeActions: resolvedActions } = resolved;

  let reduxUxSyncPending = false;

  function syncReduxUxState(reason = 'sync') {
    resolvedStore.dispatch(resolvedActions.touch({ reason, ts: Date.now() }));
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
}: InstallReduxGlobalsOptions = {}) {
  if (!windowRef || !appStore || typeof syncReduxUxState !== 'function') {
    return;
  }

  try {
    const globals = windowRef as Record<string, unknown>;
    const storeToken = String(storeKey);
    const stateToken = String(stateKey);
    const syncToken = String(syncKey);

    globals[storeToken] = appStore;
    globals[stateToken] = appStore.getState();
    appStore.subscribe(() => {
      globals[stateToken] = appStore.getState();
    });
    globals[syncToken] = (reason = 'manual') => syncReduxUxState(reason);
  } catch (_err: unknown) {
    // Ignore global assignment failures in constrained environments.
  }
}
