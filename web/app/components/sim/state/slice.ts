export const simActionTypes = {
  SET_BACKEND: 'app/setBackend',
  SET_RUNNING: 'sim/setRunning',
  SET_CYCLE: 'sim/setCycle',
  SET_UI_CYCLES_PENDING: 'sim/setUiCyclesPending'
};

type SimState = {
  backend?: string;
  running?: boolean;
  cycle?: number;
  uiCyclesPending?: number;
  [key: string]: unknown;
};

type SimAction = {
  type?: string;
  payload?: unknown;
};

export const simActions = {
  setBackend: (backend: unknown) => ({ type: simActionTypes.SET_BACKEND, payload: backend }),
  setRunning: (running: unknown) => ({ type: simActionTypes.SET_RUNNING, payload: !!running }),
  setCycle: (cycle: unknown) => ({ type: simActionTypes.SET_CYCLE, payload: Number(cycle) || 0 }),
  setUiCyclesPending: (value: unknown) => ({ type: simActionTypes.SET_UI_CYCLES_PENDING, payload: Number(value) || 0 })
};

export function createSimStateSlice() {
  return {
    backend: 'interpreter',
    running: false,
    cycle: 0,
    uiCyclesPending: 0
  };
}

export function reduceSimState(state: SimState, action: SimAction = {}) {
  switch (action.type) {
    case simActionTypes.SET_BACKEND:
      state.backend = String(action.payload || state.backend || '');
      return true;
    case simActionTypes.SET_RUNNING:
      state.running = !!action.payload;
      return true;
    case simActionTypes.SET_CYCLE:
      state.cycle = typeof action.payload === 'number' && Number.isFinite(action.payload) ? action.payload : 0;
      return true;
    case simActionTypes.SET_UI_CYCLES_PENDING:
      state.uiCyclesPending = typeof action.payload === 'number' && Number.isFinite(action.payload) ? action.payload : 0;
      return true;
    default:
      return false;
  }
}
