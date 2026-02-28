export function createShellDomainController({
  setActiveTab,
  setSidebarCollapsed,
  setTerminalOpen,
  applyTheme,
  terminalWriteLine,
  submitTerminalInput,
  terminalHistoryNavigate,
  terminalAppendInput,
  terminalBackspaceInput,
  terminalSetInput,
  terminalFocusInput,
  disposeDashboardLayoutBuilder,
  refreshDashboardRowSizing,
  refreshAllDashboardRowSizing,
  initializeDashboardLayoutBuilder
} = {}) {
  return {
    setActiveTab,
    setSidebarCollapsed,
    setTerminalOpen,
    applyTheme,
    terminal: {
      writeLine: terminalWriteLine,
      submitInput: submitTerminalInput,
      historyNavigate: terminalHistoryNavigate,
      appendInput: terminalAppendInput,
      backspaceInput: terminalBackspaceInput,
      setInput: terminalSetInput,
      focusInput: terminalFocusInput
    },
    dashboard: {
      disposeLayoutBuilder: disposeDashboardLayoutBuilder,
      refreshRowSizing: refreshDashboardRowSizing,
      refreshAllRowSizing: refreshAllDashboardRowSizing,
      initializeLayoutBuilder: initializeDashboardLayoutBuilder
    }
  };
}
