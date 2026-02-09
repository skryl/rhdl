import test from 'node:test';
import assert from 'node:assert/strict';
import { createShellStateRuntimeService } from '../../../../app/components/shell/services/state_runtime_service.mjs';

test('shell state runtime service updates terminal open state and persists toggle', () => {
  const stored = new Map();
  const state = { terminalOpen: false, sidebarCollapsed: false, theme: 'shenzhen' };
  const dom = {
    tabButtons: [],
    tabPanels: [],
    appShell: null,
    sidebarToggleBtn: null,
    terminalPanel: { hidden: true },
    terminalToggleBtn: {
      classList: { toggle() {} },
      setAttribute() {}
    },
    terminalInput: null,
    themeSelect: { value: 'shenzhen' }
  };
  const service = createShellStateRuntimeService({
    dom,
    state,
    runtime: {},
    setActiveTabState: () => {},
    setSidebarCollapsedState: () => {},
    setTerminalOpenState: (value) => {
      state.terminalOpen = !!value;
    },
    setThemeState: () => {},
    refreshAllDashboardRowSizing: () => {},
    refreshComponentExplorer: () => {},
    scheduleReduxUxSync: () => {},
    waveformFontFamily: () => 'mono',
    normalizeTheme: () => 'shenzhen',
    SIDEBAR_COLLAPSED_KEY: 's',
    TERMINAL_OPEN_KEY: 't',
    THEME_KEY: 'th',
    localStorageRef: {
      setItem(key, value) {
        stored.set(key, value);
      }
    },
    requestAnimationFrameImpl: (cb) => cb(),
    documentRef: { body: { classList: { toggle() {} } } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      constructor(type) {
        this.type = type;
      }
    }
  });

  service.setTerminalOpen(true, { persist: true });
  assert.equal(state.terminalOpen, true);
  assert.equal(dom.terminalPanel.hidden, false);
  assert.equal(stored.get('t'), '1');
});
