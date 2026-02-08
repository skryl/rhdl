import { actionTypes } from './action_types.mjs';

export const actions = {
  touch: (meta = null) => ({ type: actionTypes.TOUCH, payload: meta }),
  setBackend: (backend) => ({ type: actionTypes.SET_BACKEND, payload: backend }),
  setTheme: (theme) => ({ type: actionTypes.SET_THEME, payload: theme }),
  setRunnerPreset: (runnerPreset) => ({ type: actionTypes.SET_RUNNER_PRESET, payload: runnerPreset }),
  setActiveTab: (tabId) => ({ type: actionTypes.SET_ACTIVE_TAB, payload: tabId }),
  setSidebarCollapsed: (collapsed) => ({ type: actionTypes.SET_SIDEBAR_COLLAPSED, payload: !!collapsed }),
  setTerminalOpen: (open) => ({ type: actionTypes.SET_TERMINAL_OPEN, payload: !!open }),
  setRunning: (running) => ({ type: actionTypes.SET_RUNNING, payload: !!running }),
  setCycle: (cycle) => ({ type: actionTypes.SET_CYCLE, payload: Number(cycle) || 0 }),
  setUiCyclesPending: (value) => ({ type: actionTypes.SET_UI_CYCLES_PENDING, payload: Number(value) || 0 }),
  setMemoryFollowPc: (follow) => ({ type: actionTypes.SET_MEMORY_FOLLOW_PC, payload: !!follow }),
  setApple2DisplayHires: (value) => ({ type: actionTypes.SET_APPLE2_DISPLAY_HIRES, payload: !!value }),
  setApple2DisplayColor: (value) => ({ type: actionTypes.SET_APPLE2_DISPLAY_COLOR, payload: !!value }),
  setApple2SoundEnabled: (value) => ({ type: actionTypes.SET_APPLE2_SOUND_ENABLED, payload: !!value }),
  watchSet: (name, info = {}) => ({ type: actionTypes.WATCH_SET, payload: { name, info } }),
  watchRemove: (name) => ({ type: actionTypes.WATCH_REMOVE, payload: { name } }),
  watchClear: () => ({ type: actionTypes.WATCH_CLEAR }),
  breakpointAddOrReplace: (breakpoint) => ({ type: actionTypes.BREAKPOINT_ADD_OR_REPLACE, payload: breakpoint }),
  breakpointRemove: (name) => ({ type: actionTypes.BREAKPOINT_REMOVE, payload: { name } }),
  breakpointClear: () => ({ type: actionTypes.BREAKPOINT_CLEAR }),
  mutate: (mutator) => ({ type: actionTypes.MUTATE, payload: mutator })
};
