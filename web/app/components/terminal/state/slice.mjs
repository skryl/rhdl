export function createTerminalStateSlice() {
  return {
    terminal: {
      history: [],
      historyIndex: -1,
      busy: false,
      lines: [],
      inputBuffer: ''
    }
  };
}

export function reduceTerminalState(_state, _action = {}) {
  return false;
}
