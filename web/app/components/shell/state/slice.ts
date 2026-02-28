export const shellActionTypes = {
  SET_THEME: 'app/setTheme',
  SET_ACTIVE_TAB: 'app/setActiveTab',
  SET_SIDEBAR_COLLAPSED: 'app/setSidebarCollapsed',
  SET_TERMINAL_OPEN: 'app/setTerminalOpen'
};

export const shellActions = {
  setTheme: (theme) => ({ type: shellActionTypes.SET_THEME, payload: theme }),
  setActiveTab: (tabId) => ({ type: shellActionTypes.SET_ACTIVE_TAB, payload: tabId }),
  setSidebarCollapsed: (collapsed) => ({ type: shellActionTypes.SET_SIDEBAR_COLLAPSED, payload: !!collapsed }),
  setTerminalOpen: (open) => ({ type: shellActionTypes.SET_TERMINAL_OPEN, payload: !!open })
};

export function createShellStateSlice() {
  return {
    theme: 'shenzhen',
    sidebarCollapsed: false,
    terminalOpen: false,
    activeTab: 'ioTab',
    dashboard: {
      rootElements: new Map(),
      layouts: {},
      draggingItemId: '',
      draggingRootKey: '',
      dropTargetItemId: '',
      dropPosition: '',
      resizeBound: false,
      resizeTeardown: null,
      panelTeardowns: new Map(),
      resizing: {
        active: false,
        rootKey: '',
        rowSignature: '',
        startY: 0,
        startHeight: 140
      }
    }
  };
}

export function reduceShellState(state, action = {}) {
  switch (action.type) {
    case shellActionTypes.SET_THEME:
      state.theme = String(action.payload || state.theme || '');
      return true;
    case shellActionTypes.SET_ACTIVE_TAB:
      state.activeTab = String(action.payload || state.activeTab || '');
      return true;
    case shellActionTypes.SET_SIDEBAR_COLLAPSED:
      state.sidebarCollapsed = !!action.payload;
      return true;
    case shellActionTypes.SET_TERMINAL_OPEN:
      state.terminalOpen = !!action.payload;
      return true;
    default:
      return false;
  }
}
