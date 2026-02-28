export function createTerminalStateSlice() {
  return {
    terminal: {
      history: [],
      historyIndex: -1,
      busy: false,
      lines: [],
      inputBuffer: '',
      uartPassthrough: false
    }
  };
}

export function reduceTerminalState(_state: any, _action = {}) {
  return false;
}
