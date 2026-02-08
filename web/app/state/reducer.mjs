import { actionTypes } from './action_types.mjs';

export function reduceState(state, action = {}) {
  switch (action.type) {
    case actionTypes.TOUCH:
      state.__lastReduxMeta = action.payload || null;
      return state;
    case actionTypes.SET_BACKEND:
      state.backend = String(action.payload || state.backend || '');
      return state;
    case actionTypes.SET_THEME:
      state.theme = String(action.payload || state.theme || '');
      return state;
    case actionTypes.SET_RUNNER_PRESET:
      state.runnerPreset = String(action.payload || state.runnerPreset || '');
      return state;
    case actionTypes.SET_ACTIVE_TAB:
      state.activeTab = String(action.payload || state.activeTab || '');
      return state;
    case actionTypes.SET_SIDEBAR_COLLAPSED:
      state.sidebarCollapsed = !!action.payload;
      return state;
    case actionTypes.SET_TERMINAL_OPEN:
      state.terminalOpen = !!action.payload;
      return state;
    case actionTypes.SET_RUNNING:
      state.running = !!action.payload;
      return state;
    case actionTypes.SET_CYCLE:
      state.cycle = Number.isFinite(action.payload) ? action.payload : 0;
      return state;
    case actionTypes.SET_UI_CYCLES_PENDING:
      state.uiCyclesPending = Number.isFinite(action.payload) ? action.payload : 0;
      return state;
    case actionTypes.SET_MEMORY_FOLLOW_PC:
      if (!state.memory || typeof state.memory !== 'object') {
        state.memory = {};
      }
      state.memory.followPc = !!action.payload;
      return state;
    case actionTypes.SET_APPLE2_DISPLAY_HIRES:
      if (!state.apple2 || typeof state.apple2 !== 'object') {
        state.apple2 = {};
      }
      state.apple2.displayHires = !!action.payload;
      return state;
    case actionTypes.SET_APPLE2_DISPLAY_COLOR:
      if (!state.apple2 || typeof state.apple2 !== 'object') {
        state.apple2 = {};
      }
      state.apple2.displayColor = !!action.payload;
      return state;
    case actionTypes.SET_APPLE2_SOUND_ENABLED:
      if (!state.apple2 || typeof state.apple2 !== 'object') {
        state.apple2 = {};
      }
      state.apple2.soundEnabled = !!action.payload;
      return state;
    case actionTypes.WATCH_SET: {
      const name = String(action.payload?.name || '').trim();
      if (!name) {
        return state;
      }
      if (!(state.watches instanceof Map)) {
        state.watches = new Map();
      }
      const info = action.payload?.info && typeof action.payload.info === 'object'
        ? action.payload.info
        : {};
      state.watches.set(name, info);
      return state;
    }
    case actionTypes.WATCH_REMOVE: {
      const name = String(action.payload?.name || '').trim();
      if (!name || !(state.watches instanceof Map)) {
        return state;
      }
      state.watches.delete(name);
      return state;
    }
    case actionTypes.WATCH_CLEAR:
      if (state.watches instanceof Map) {
        state.watches.clear();
      } else {
        state.watches = new Map();
      }
      return state;
    case actionTypes.BREAKPOINT_ADD_OR_REPLACE: {
      const bp = action.payload;
      const name = String(bp?.name || '').trim();
      if (!name) {
        return state;
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
      return state;
    }
    case actionTypes.BREAKPOINT_REMOVE: {
      const name = String(action.payload?.name || '').trim();
      if (!name || !Array.isArray(state.breakpoints)) {
        return state;
      }
      state.breakpoints = state.breakpoints.filter((entry) => entry?.name !== name);
      return state;
    }
    case actionTypes.BREAKPOINT_CLEAR:
      state.breakpoints = [];
      return state;
    case actionTypes.MUTATE:
      if (typeof action.payload === 'function') {
        action.payload(state);
      }
      return state;
    default:
      return state;
  }
}
