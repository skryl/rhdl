export const watchActionTypes = {
  WATCH_SET: 'watch/set',
  WATCH_REMOVE: 'watch/remove',
  WATCH_CLEAR: 'watch/clear',
  BREAKPOINT_ADD_OR_REPLACE: 'breakpoint/addOrReplace',
  BREAKPOINT_REMOVE: 'breakpoint/remove',
  BREAKPOINT_CLEAR: 'breakpoint/clear'
};

export const watchActions = {
  watchSet: (name, info = {}) => ({ type: watchActionTypes.WATCH_SET, payload: { name, info } }),
  watchRemove: (name) => ({ type: watchActionTypes.WATCH_REMOVE, payload: { name } }),
  watchClear: () => ({ type: watchActionTypes.WATCH_CLEAR }),
  breakpointAddOrReplace: (breakpoint) => ({ type: watchActionTypes.BREAKPOINT_ADD_OR_REPLACE, payload: breakpoint }),
  breakpointRemove: (name) => ({ type: watchActionTypes.BREAKPOINT_REMOVE, payload: { name } }),
  breakpointClear: () => ({ type: watchActionTypes.BREAKPOINT_CLEAR })
};

export function createWatchStateSlice() {
  return {
    watches: new Map(),
    watchRows: [],
    breakpoints: []
  };
}

export function reduceWatchState(state, action = {}) {
  switch (action.type) {
    case watchActionTypes.WATCH_SET: {
      const name = String(action.payload?.name || '').trim();
      if (!name) {
        return true;
      }
      if (!(state.watches instanceof Map)) {
        state.watches = new Map();
      }
      const info = action.payload?.info && typeof action.payload.info === 'object'
        ? action.payload.info
        : {};
      state.watches.set(name, info);
      return true;
    }
    case watchActionTypes.WATCH_REMOVE: {
      const name = String(action.payload?.name || '').trim();
      if (!name || !(state.watches instanceof Map)) {
        return true;
      }
      state.watches.delete(name);
      return true;
    }
    case watchActionTypes.WATCH_CLEAR:
      if (state.watches instanceof Map) {
        state.watches.clear();
      } else {
        state.watches = new Map();
      }
      return true;
    case watchActionTypes.BREAKPOINT_ADD_OR_REPLACE: {
      const bp = action.payload;
      const name = String(bp?.name || '').trim();
      if (!name) {
        return true;
      }
      if (!Array.isArray(state.breakpoints)) {
        state.breakpoints = [];
      }
      const next = { ...bp, name };
      const idx = state.breakpoints.findIndex((entry) => entry?.name === name);
      if (idx >= 0) {
        state.breakpoints[idx] = next;
      } else {
        state.breakpoints.push(next);
      }
      return true;
    }
    case watchActionTypes.BREAKPOINT_REMOVE: {
      const name = String(action.payload?.name || '').trim();
      if (!name || !Array.isArray(state.breakpoints)) {
        return true;
      }
      state.breakpoints = state.breakpoints.filter((entry) => entry?.name !== name);
      return true;
    }
    case watchActionTypes.BREAKPOINT_CLEAR:
      state.breakpoints = [];
      return true;
    default:
      return false;
  }
}
