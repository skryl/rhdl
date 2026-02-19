export const simActionTypes = {
  SET_BACKEND: 'app/setBackend',
  SET_RUNNING: 'sim/setRunning',
  SET_CYCLE: 'sim/setCycle',
  SET_UI_CYCLES_PENDING: 'sim/setUiCyclesPending'
};

export const simActions = {
  setBackend: (backend) => ({ type: simActionTypes.SET_BACKEND, payload: backend }),
  setRunning: (running) => ({ type: simActionTypes.SET_RUNNING, payload: !!running }),
  setCycle: (cycle) => ({ type: simActionTypes.SET_CYCLE, payload: Number(cycle) || 0 }),
  setUiCyclesPending: (value) => ({ type: simActionTypes.SET_UI_CYCLES_PENDING, payload: Number(value) || 0 })
};

export function createSimStateSlice() {
  return {
    backend: 'interpreter',
    running: false,
    cycle: 0,
    uiCyclesPending: 0
  };
}

export function reduceSimState(state, action = {}) {
  switch (action.type) {
    case simActionTypes.SET_BACKEND:
      state.backend = String(action.payload || state.backend || '');
      return true;
    case simActionTypes.SET_RUNNING:
      state.running = !!action.payload;
      return true;
    case simActionTypes.SET_CYCLE:
      state.cycle = Number.isFinite(action.payload) ? action.payload : 0;
      return true;
    case simActionTypes.SET_UI_CYCLES_PENDING:
      state.uiCyclesPending = Number.isFinite(action.payload) ? action.payload : 0;
      return true;
    default:
      return false;
  }
}
