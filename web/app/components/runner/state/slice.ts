export const runnerActionTypes = {
  SET_RUNNER_PRESET: 'app/setRunnerPreset'
};

type RunnerAction = {
  type?: string;
  payload?: unknown;
};

type RunnerState = {
  runnerPreset?: string;
  [key: string]: unknown;
};

export const runnerActions = {
  setRunnerPreset: (runnerPreset: unknown) => ({ type: runnerActionTypes.SET_RUNNER_PRESET, payload: runnerPreset })
};

export function createRunnerStateSlice() {
  return {
    runnerPreset: 'apple2'
  };
}

export function reduceRunnerState(state: RunnerState, action: RunnerAction = {}) {
  switch (action.type) {
    case runnerActionTypes.SET_RUNNER_PRESET:
      state.runnerPreset = String(action.payload || state.runnerPreset || '');
      return true;
    default:
      return false;
  }
}
