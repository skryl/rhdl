export const runnerActionTypes = {
  SET_RUNNER_PRESET: 'app/setRunnerPreset'
};

export const runnerActions = {
  setRunnerPreset: (runnerPreset: any) => ({ type: runnerActionTypes.SET_RUNNER_PRESET, payload: runnerPreset })
};

export function createRunnerStateSlice() {
  return {
    runnerPreset: 'apple2'
  };
}

export function reduceRunnerState(state: any, action: any = {}) {
  switch (action.type) {
    case runnerActionTypes.SET_RUNNER_PRESET:
      state.runnerPreset = String(action.payload || state.runnerPreset || '');
      return true;
    default:
      return false;
  }
}
