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

export function reduceTerminalState(_state: unknown, _action: unknown = {}) {
  return false;
}
