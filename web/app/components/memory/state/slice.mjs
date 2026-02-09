export const memoryActionTypes = {
  SET_MEMORY_FOLLOW_PC: 'memory/setFollowPc'
};

export const memoryActions = {
  setMemoryFollowPc: (follow) => ({ type: memoryActionTypes.SET_MEMORY_FOLLOW_PC, payload: !!follow })
};

export function createMemoryStateSlice() {
  return {
    memory: {
      followPc: false,
      disasmLines: 28,
      lastSavedDump: null
    }
  };
}

export function reduceMemoryState(state, action = {}) {
  switch (action.type) {
    case memoryActionTypes.SET_MEMORY_FOLLOW_PC:
      if (!state.memory || typeof state.memory !== 'object') {
        state.memory = {};
      }
      state.memory.followPc = !!action.payload;
      return true;
    default:
      return false;
  }
}
