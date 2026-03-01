import test from 'node:test';
import assert from 'node:assert/strict';

import { createShellStateController } from '../../../../app/components/shell/controllers/state_controller';

function classListStub() {
  const calls: Array<{ name: string; value: boolean }> = [];
  return {
    calls,
    toggle(name: string, value: boolean) {
      calls.push({ name, value });
    }
  };
}

test('setActiveTab updates tabs and schedules sync', () => {
  const tabClass = classListStub();
  const panelClass = classListStub();
  const dom = {
    tabButtons: [{ dataset: { tab: 'vcdTab' }, classList: tabClass, setAttribute() {} }],
    tabPanels: [{ id: 'vcdTab', classList: panelClass }],
    appShell: null,
    sidebarToggleBtn: null,
    terminalPanel: null,
    terminalToggleBtn: null,
    terminalInput: null,
    themeSelect: { value: 'shenzhen' }
  };
  const state = { activeTab: 'ioTab', theme: 'shenzhen', terminalOpen: false, sidebarCollapsed: false };
  const runtime = {};
  const syncReasons: string[] = [];
  const rafCalls: string[] = [];

  const controller = createShellStateController({
    dom,
    state,
    runtime,
    setActiveTabState: (value: string) => {
      state.activeTab = value;
    },
    setSidebarCollapsedState: () => {},
    setTerminalOpenState: () => {},
    setThemeState: () => {},
    refreshAllDashboardRowSizing: () => {},
    refreshComponentExplorer: () => {
      rafCalls.push('refreshComponentExplorer');
    },
    scheduleReduxUxSync: (reason: string) => {
      syncReasons.push(reason);
    },
    waveformFontFamily: () => 'mono',
    normalizeTheme: () => 'shenzhen',
    SIDEBAR_COLLAPSED_KEY: 's',
    TERMINAL_OPEN_KEY: 't',
    THEME_KEY: 'th',
    localStorageRef: { setItem() {} },
    requestAnimationFrameImpl: (cb: () => void) => {
      rafCalls.push('raf');
      cb();
    },
    documentRef: { body: { classList: classListStub() } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      type: string;
      constructor(type: string) {
        this.type = type;
      }
    }
  });

  controller.setActiveTab('vcdTab');

  assert.equal(state.activeTab, 'vcdTab');
  assert.equal(tabClass.calls[0].name, 'active');
  assert.equal(panelClass.calls[0].name, 'active');
  assert.deepEqual(syncReasons, ['setActiveTab']);
  assert.ok(rafCalls.includes('raf'));
});

test('applyTheme normalizes/persists and updates body class', () => {
  const bodyClass = classListStub();
  const stored = new Map();
  const state = { theme: 'shenzhen', terminalOpen: false, sidebarCollapsed: false };
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
  const runtime: { waveformP5: { textFont(value: string): void }; lastFont?: string } = {
    waveformP5: {
      textFont(value: string) {
        runtime.lastFont = value;
      }
    }
  };
  const syncReasons: string[] = [];

  const controller = createShellStateController({
    dom,
    state,
    runtime,
    setActiveTabState: () => {},
    setSidebarCollapsedState: () => {},
    setTerminalOpenState: () => {},
    setThemeState: (value: string) => {
      state.theme = value;
    },
    refreshAllDashboardRowSizing: () => {},
    refreshComponentExplorer: () => {},
    scheduleReduxUxSync: (reason: string) => {
      syncReasons.push(reason);
    },
    waveformFontFamily: (theme: string) => `font:${theme}`,
    normalizeTheme: () => 'original',
    SIDEBAR_COLLAPSED_KEY: 's',
    TERMINAL_OPEN_KEY: 't',
    THEME_KEY: 'th',
    localStorageRef: {
      setItem(key: string, value: string) {
        stored.set(key, value);
      }
    },
    requestAnimationFrameImpl: (cb: () => void) => cb(),
    documentRef: { body: { classList: bodyClass } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      type: string;
      constructor(type: string) {
        this.type = type;
      }
    }
  });

  controller.applyTheme('anything', { persist: true });

  assert.equal(state.theme, 'original');
  assert.equal(dom.themeSelect.value, 'original');
  assert.equal(runtime.lastFont, 'font:original');
  assert.equal(stored.get('th'), 'original');
  assert.deepEqual(syncReasons, ['applyTheme']);
  assert.equal(bodyClass.calls[0].name, 'theme-shenzhen');
  assert.equal(bodyClass.calls[0].value, false);
});
