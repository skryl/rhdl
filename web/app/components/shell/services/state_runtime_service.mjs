function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createShellStateRuntimeService requires function: ${name}`);
  }
}

export function createShellStateRuntimeService({
  dom,
  state,
  runtime,
  setActiveTabState,
  setSidebarCollapsedState,
  setTerminalOpenState,
  setThemeState,
  refreshAllDashboardRowSizing,
  refreshComponentExplorer,
  scheduleReduxUxSync,
  waveformFontFamily,
  normalizeTheme,
  SIDEBAR_COLLAPSED_KEY,
  TERMINAL_OPEN_KEY,
  THEME_KEY,
  localStorageRef = globalThis.localStorage,
  requestAnimationFrameImpl = globalThis.requestAnimationFrame,
  documentRef = globalThis.document,
  windowRef = globalThis.window,
  eventCtor = globalThis.Event
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createShellStateRuntimeService requires dom/state/runtime');
  }
  requireFn('setActiveTabState', setActiveTabState);
  requireFn('setSidebarCollapsedState', setSidebarCollapsedState);
  requireFn('setTerminalOpenState', setTerminalOpenState);
  requireFn('setThemeState', setThemeState);
  requireFn('refreshAllDashboardRowSizing', refreshAllDashboardRowSizing);
  requireFn('refreshComponentExplorer', refreshComponentExplorer);
  requireFn('scheduleReduxUxSync', scheduleReduxUxSync);
  requireFn('waveformFontFamily', waveformFontFamily);
  requireFn('normalizeTheme', normalizeTheme);

  function setActiveTab(tabId) {
    setActiveTabState(tabId);
    for (const btn of dom.tabButtons) {
      const selected = btn.dataset.tab === tabId;
      btn.classList.toggle('active', selected);
      btn.setAttribute('aria-selected', selected ? 'true' : 'false');
    }
    for (const panel of dom.tabPanels) {
      panel.classList.toggle('active', panel.id === tabId);
    }
    requestAnimationFrameImpl(() => {
      refreshAllDashboardRowSizing();
    });

    if (tabId === 'vcdTab') {
      requestAnimationFrameImpl(() => {
        windowRef.dispatchEvent(new eventCtor('resize'));
      });
    }
    if (tabId === 'componentTab' || tabId === 'componentGraphTab') {
      refreshComponentExplorer();
    }
    scheduleReduxUxSync('setActiveTab');
  }

  function setSidebarCollapsed(collapsed) {
    setSidebarCollapsedState(!!collapsed);
    if (dom.appShell) {
      dom.appShell.classList.toggle('controls-collapsed', state.sidebarCollapsed);
    }
    if (dom.sidebarToggleBtn) {
      dom.sidebarToggleBtn.setAttribute('aria-expanded', state.sidebarCollapsed ? 'false' : 'true');
      dom.sidebarToggleBtn.setAttribute('aria-label', state.sidebarCollapsed ? 'Show Config' : 'Hide Config');
      dom.sidebarToggleBtn.setAttribute('title', state.sidebarCollapsed ? 'Show Config' : 'Hide Config');
      dom.sidebarToggleBtn.classList.toggle('is-active', !state.sidebarCollapsed);
    }
    try {
      localStorageRef.setItem(SIDEBAR_COLLAPSED_KEY, state.sidebarCollapsed ? '1' : '0');
    } catch (_err) {
      // Ignore storage failures (private mode, policy, etc).
    }
    requestAnimationFrameImpl(() => {
      refreshAllDashboardRowSizing();
    });
    scheduleReduxUxSync('setSidebarCollapsed');
  }

  function setTerminalOpen(open, { persist = true, focus = false } = {}) {
    setTerminalOpenState(!!open);
    if (dom.terminalPanel) {
      dom.terminalPanel.hidden = !state.terminalOpen;
    }
    if (dom.terminalToggleBtn) {
      dom.terminalToggleBtn.classList.toggle('is-active', state.terminalOpen);
      dom.terminalToggleBtn.setAttribute('aria-expanded', state.terminalOpen ? 'true' : 'false');
      dom.terminalToggleBtn.setAttribute('aria-label', state.terminalOpen ? 'Hide Terminal' : 'Show Terminal');
      dom.terminalToggleBtn.setAttribute('title', state.terminalOpen ? 'Hide Terminal' : 'Show Terminal');
    }
    if (persist) {
      try {
        localStorageRef.setItem(TERMINAL_OPEN_KEY, state.terminalOpen ? '1' : '0');
      } catch (_err) {
        // Ignore storage failures.
      }
    }
    requestAnimationFrameImpl(() => {
      refreshAllDashboardRowSizing();
    });
    if (state.terminalOpen && focus && dom.terminalInput) {
      requestAnimationFrameImpl(() => {
        dom.terminalInput.focus();
        dom.terminalInput.select();
      });
    }
    scheduleReduxUxSync('setTerminalOpen');
  }

  function applyTheme(theme, { persist = true } = {}) {
    const nextTheme = normalizeTheme(theme);
    setThemeState(nextTheme);
    if (documentRef.body) {
      documentRef.body.classList.toggle('theme-shenzhen', nextTheme === 'shenzhen');
    }
    if (dom.themeSelect && dom.themeSelect.value !== nextTheme) {
      dom.themeSelect.value = nextTheme;
    }
    if (runtime.waveformP5 && typeof runtime.waveformP5.textFont === 'function') {
      runtime.waveformP5.textFont(waveformFontFamily(state.theme));
    }
    if (persist) {
      try {
        localStorageRef.setItem(THEME_KEY, nextTheme);
      } catch (_err) {
        // Ignore storage failures.
      }
    }
    scheduleReduxUxSync('applyTheme');
  }

  return {
    setActiveTab,
    setSidebarCollapsed,
    setTerminalOpen,
    applyTheme
  };
}
