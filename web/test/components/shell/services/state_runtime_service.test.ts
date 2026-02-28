import test from 'node:test';
import assert from 'node:assert/strict';
import { createShellStateRuntimeService } from '../../../../app/components/shell/services/state_runtime_service';

test('shell state runtime service updates terminal open state and persists toggle', () => {
  const stored = new Map();
  const appShellClasses = new Map();
  const state = { terminalOpen: false, sidebarCollapsed: false, theme: 'shenzhen' };
  const dom = {
    tabButtons: [],
    tabPanels: [],
    appShell: {
      classList: {
        toggle(name: any, active: any) {
          appShellClasses.set(String(name), !!active);
        }
      }
    },
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
    setTerminalOpenState: (value: any) => {
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
      setItem(key: any, value: any) {
        stored.set(key, value);
      }
    },
    requestAnimationFrameImpl: (cb: any) => cb(),
    documentRef: { body: { classList: { toggle() {} } } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      type: any;
      constructor(type: any) {
        this.type = type;
      }
    }
  });

  service.setTerminalOpen(true, { persist: true });
  assert.equal(state.terminalOpen, true);
  assert.equal(appShellClasses.get('terminal-open'), true);
  assert.equal(dom.terminalPanel.hidden, false);
  assert.equal(stored.get('t'), '1');
});

test('shell state runtime service defers and deduplicates component explorer refresh on tab switch', () => {
  const pendingTimers: any[] = [];
  let refreshCalls = 0;
  const state = { activeTab: 'ioTab', terminalOpen: false, sidebarCollapsed: false, theme: 'shenzhen' };
  const dom = {
    tabButtons: [],
    tabPanels: [],
    appShell: null,
    sidebarToggleBtn: null,
    terminalPanel: null,
    terminalToggleBtn: null,
    terminalInput: null,
    themeSelect: { value: 'shenzhen' }
  };
  const service = createShellStateRuntimeService({
    dom,
    state,
    runtime: {},
    setActiveTabState: (value: any) => {
      state.activeTab = value;
    },
    setSidebarCollapsedState: () => {},
    setTerminalOpenState: () => {},
    setThemeState: () => {},
    refreshAllDashboardRowSizing: () => {},
    refreshComponentExplorer: () => {
      refreshCalls += 1;
    },
    scheduleReduxUxSync: () => {},
    waveformFontFamily: () => 'mono',
    normalizeTheme: () => 'shenzhen',
    SIDEBAR_COLLAPSED_KEY: 's',
    TERMINAL_OPEN_KEY: 't',
    THEME_KEY: 'th',
    localStorageRef: { setItem() {} },
    requestAnimationFrameImpl: (cb: any) => cb(),
    setTimeoutImpl: (cb: any) => {
      pendingTimers.push(cb);
    },
    documentRef: { body: { classList: { toggle() {} } } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      type: any;
      constructor(type: any) {
        this.type = type;
      }
    }
  });

  service.setActiveTab('componentGraphTab');
  service.setActiveTab('componentTab');

  assert.equal(refreshCalls, 0);
  assert.equal(pendingTimers.length, 1);

  pendingTimers.shift()();

  assert.equal(refreshCalls, 1);
});
