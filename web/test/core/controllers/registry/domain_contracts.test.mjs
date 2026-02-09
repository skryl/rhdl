import test from 'node:test';
import assert from 'node:assert/strict';

import { createShellDomainController } from '../../../../app/components/shell/controllers/domain.mjs';
import { createRunnerDomainController } from '../../../../app/components/runner/controllers/domain.mjs';
import { createComponentDomainController } from '../../../../app/components/explorer/controllers/domain.mjs';
import { createApple2DomainController } from '../../../../app/components/apple2/controllers/domain.mjs';
import { createSimDomainController } from '../../../../app/components/sim/controllers/domain.mjs';
import { createWatchDomainController } from '../../../../app/components/watch/controllers/domain.mjs';

test('registry domains expose the grouped controller contracts used by startup + bindings', () => {
  const fn = () => {};

  const shell = createShellDomainController({
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
  const runner = createRunnerDomainController({
    getRunnerPreset: fn,
    currentRunnerPreset: fn,
    loadRunnerPreset: fn,
    loadSample: fn,
    loadRunnerIrBundle: fn,
    updateIrSourceVisibility: fn,
    getRunnerActionsController: fn,
    ensureBackendInstance: fn
  });
  const components = createComponentDomainController({
    isComponentTabActive: fn,
    refreshActiveComponentTab: fn,
    refreshComponentExplorer: fn,
    renderComponentTree: fn,
    setComponentGraphFocus: fn,
    currentComponentGraphFocusNode: fn,
    renderComponentViews: fn,
    clearComponentSourceOverride: fn,
    resetComponentExplorerState: fn
  });
  const apple2 = createApple2DomainController({
    isApple2UiEnabled: fn,
    updateIoToggleUi: fn,
    refreshApple2Screen: fn,
    refreshApple2Debug: fn,
    refreshMemoryView: fn,
    setApple2SoundEnabled: fn,
    updateApple2SpeakerAudio: fn,
    queueApple2Key: fn,
    performApple2ResetSequence: fn,
    setMemoryDumpStatus: fn,
    loadApple2DumpOrSnapshotFile: fn,
    saveApple2MemoryDump: fn,
    saveApple2MemorySnapshot: fn,
    loadLastSavedApple2Dump: fn,
    loadKaratekaDump: fn,
    resetApple2WithMemoryVectorOverride: fn
  });
  const sim = createSimDomainController({
    setupP5: fn,
    refreshStatus: fn,
    initializeSimulator: fn,
    initializeTrace: fn,
    stepSimulation: fn,
    runFrame: fn,
    drainTrace: fn,
    maskForWidth: fn
  });
  const watch = createWatchDomainController({
    refreshWatchTable: fn,
    addWatchSignal: fn,
    removeWatchSignal: fn,
    addBreakpointSignal: fn,
    clearAllBreakpoints: fn,
    removeBreakpointSignal: fn,
    renderBreakpointList: fn
  });

  assert.equal(shell.terminal.submitInput, fn);
  assert.equal(shell.dashboard.refreshRowSizing, fn);
  assert.equal(runner.getActionsController, fn);
  assert.equal(components.refreshExplorer, fn);
  assert.equal(components.currentGraphFocusNode, fn);
  assert.equal(apple2.resetWithMemoryVectorOverride, fn);
  assert.equal(apple2.loadDumpOrSnapshotFile, fn);
  assert.equal(sim.initializeSimulator, fn);
  assert.equal(sim.maskForWidth, fn);
  assert.equal(watch.addBreakpoint, fn);
  assert.equal(watch.renderBreakpoints, fn);
});
