export const memoryActionTypes = {
  SET_MEMORY_FOLLOW_PC: 'memory/setFollowPc',
  SET_MEMORY_SHOW_SOURCE: 'memory/setShowSource'
};

export const memoryActions = {
  setMemoryFollowPc: (follow: any) => ({ type: memoryActionTypes.SET_MEMORY_FOLLOW_PC, payload: !!follow }),
  setMemoryShowSource: (show: any) => ({ type: memoryActionTypes.SET_MEMORY_SHOW_SOURCE, payload: !!show })
};

export function createMemoryStateSlice() {
  return {
    memory: {
      followPc: false,
      showSource: false,
      disasmLines: 28,
      lastSavedDump: null
    }
  };
}

export function reduceMemoryState(state: any, action: any = {}) {
  switch (action.type) {
    case memoryActionTypes.SET_MEMORY_FOLLOW_PC:
      if (!state.memory || typeof state.memory !== 'object') {
        state.memory = {};
      }
      state.memory.followPc = !!action.payload;
      return true;
    case memoryActionTypes.SET_MEMORY_SHOW_SOURCE:
      if (!state.memory || typeof state.memory !== 'object') {
        state.memory = {};
      }
      state.memory.showSource = !!action.payload;
      return true;
    default:
      return false;
  }
}
