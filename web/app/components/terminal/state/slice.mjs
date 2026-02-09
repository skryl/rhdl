export function createTerminalStateSlice() {
  return {
    terminal: {
      history: [],
      historyIndex: -1,
      busy: false
    }
  };
}

export function reduceTerminalState(_state, _action = {}) {
  return false;
}
