import test from 'node:test';
import assert from 'node:assert/strict';
import { createShellDomainController } from '../../app/controllers/registry_shell_domain_controller.mjs';

test('createShellDomainController groups shell, terminal, and dashboard actions', () => {
  const fn = () => {};
  const domain = createShellDomainController({
    setActiveTab: fn,
    setSidebarCollapsed: fn,
    setTerminalOpen: fn,
    applyTheme: fn,
    terminalWriteLine: fn,
    submitTerminalInput: fn,
    terminalHistoryNavigate: fn,
    disposeDashboardLayoutBuilder: fn,
    refreshDashboardRowSizing: fn,
    refreshAllDashboardRowSizing: fn,
    initializeDashboardLayoutBuilder: fn
  });

  assert.equal(domain.setActiveTab, fn);
  assert.equal(domain.terminal.writeLine, fn);
  assert.equal(domain.dashboard.refreshAllRowSizing, fn);
});
