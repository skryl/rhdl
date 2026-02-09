import test from 'node:test';
import assert from 'node:assert/strict';

import { createShellStateController } from '../../../../app/components/shell/controllers/state_controller.mjs';

function classListStub() {
  const calls = [];
  return {
    calls,
    toggle(name, value) {
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
  const syncReasons = [];
  const rafCalls = [];

  const controller = createShellStateController({
    dom,
    state,
    runtime,
    setActiveTabState: (value) => {
      state.activeTab = value;
    },
    setSidebarCollapsedState: () => {},
    setTerminalOpenState: () => {},
    setThemeState: () => {},
    refreshAllDashboardRowSizing: () => {},
    refreshComponentExplorer: () => {
      rafCalls.push('refreshComponentExplorer');
    },
    scheduleReduxUxSync: (reason) => {
      syncReasons.push(reason);
    },
    waveformFontFamily: () => 'mono',
    normalizeTheme: () => 'shenzhen',
    SIDEBAR_COLLAPSED_KEY: 's',
    TERMINAL_OPEN_KEY: 't',
    THEME_KEY: 'th',
    localStorageRef: { setItem() {} },
    requestAnimationFrameImpl: (cb) => {
      rafCalls.push('raf');
      cb();
    },
    documentRef: { body: { classList: classListStub() } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      constructor(type) {
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
  const runtime = {
    waveformP5: {
      textFont(value) {
        runtime.lastFont = value;
      }
    }
  };
  const syncReasons = [];

  const controller = createShellStateController({
    dom,
    state,
    runtime,
    setActiveTabState: () => {},
    setSidebarCollapsedState: () => {},
    setTerminalOpenState: () => {},
    setThemeState: (value) => {
      state.theme = value;
    },
    refreshAllDashboardRowSizing: () => {},
    refreshComponentExplorer: () => {},
    scheduleReduxUxSync: (reason) => {
      syncReasons.push(reason);
    },
    waveformFontFamily: (theme) => `font:${theme}`,
    normalizeTheme: () => 'original',
    SIDEBAR_COLLAPSED_KEY: 's',
    TERMINAL_OPEN_KEY: 't',
    THEME_KEY: 'th',
    localStorageRef: {
      setItem(key, value) {
        stored.set(key, value);
      }
    },
    requestAnimationFrameImpl: (cb) => cb(),
    documentRef: { body: { classList: bodyClass } },
    windowRef: { dispatchEvent() {} },
    eventCtor: class {
      constructor(type) {
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
