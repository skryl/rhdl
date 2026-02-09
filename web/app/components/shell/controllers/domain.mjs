export function createShellDomainController({
  setActiveTab,
  setSidebarCollapsed,
  setTerminalOpen,
  applyTheme,
  terminalWriteLine,
  submitTerminalInput,
  terminalHistoryNavigate,
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
      historyNavigate: terminalHistoryNavigate
    },
    dashboard: {
      disposeLayoutBuilder: disposeDashboardLayoutBuilder,
      refreshRowSizing: refreshDashboardRowSizing,
      refreshAllRowSizing: refreshAllDashboardRowSizing,
      initializeLayoutBuilder: initializeDashboardLayoutBuilder
    }
  };
}
