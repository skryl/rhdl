import test from 'node:test';
import assert from 'node:assert/strict';

import { createShellDomainController } from '../../../../app/components/shell/controllers/domain';
import { createRunnerDomainController } from '../../../../app/components/runner/controllers/domain';
import { createComponentDomainController } from '../../../../app/components/explorer/controllers/domain';
import { createApple2DomainController } from '../../../../app/components/apple2/controllers/domain';
import { createSimDomainController } from '../../../../app/components/sim/controllers/domain';
import { createWatchDomainController } from '../../../../app/components/watch/controllers/domain';

test('registry domains expose the grouped controller contracts used by startup + bindings', () => {
  const fn = () => {};
  const fnBool = () => true;
  const fnAsyncBool = async () => true;
  const fnAsyncVoid = async () => {};
  const fnUnknown = () => null;
  const fnBigInt = () => 0n;

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
    isComponentTabActive: fnBool,
    refreshActiveComponentTab: fn,
    refreshComponentExplorer: fn,
    renderComponentTree: fn,
    setComponentGraphFocus: fn,
    currentComponentGraphFocusNode: fn,
    renderComponentViews: fn,
    zoomComponentGraphIn: fn,
    zoomComponentGraphOut: fn,
    resetComponentGraphViewport: fn,
    clearComponentSourceOverride: fn,
    resetComponentExplorerState: fn
  });
  const apple2 = createApple2DomainController({
    isApple2UiEnabled: fn,
    updateIoToggleUi: fn,
    refreshApple2Screen: fn,
    refreshApple2Debug: fn,
    refreshMemoryView: fn,
    setApple2SoundEnabled: fnAsyncVoid,
    updateApple2SpeakerAudio: fn,
    queueApple2Key: fn,
    performApple2ResetSequence: fnUnknown,
    setMemoryDumpStatus: fn,
    loadApple2DumpOrSnapshotFile: fnAsyncBool,
    loadApple2DumpOrSnapshotAssetPath: fnAsyncBool,
    saveApple2MemoryDump: fnAsyncBool,
    saveApple2MemorySnapshot: fnAsyncBool,
    loadLastSavedApple2Dump: fnAsyncBool,
    loadKaratekaDump: fnAsyncVoid,
    resetApple2WithMemoryVectorOverride: fnAsyncBool
  });
  const sim = createSimDomainController({
    setupP5: fn,
    refreshStatus: fn,
    initializeSimulator: fn,
    initializeTrace: fn,
    stepSimulation: fn,
    runFrame: fn,
    drainTrace: fn,
    maskForWidth: fnBigInt
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
  assert.equal(components.resetGraphView, fn);
  assert.equal(apple2.resetWithMemoryVectorOverride, fnAsyncBool);
  assert.equal(apple2.loadDumpOrSnapshotFile, fnAsyncBool);
  assert.equal(sim.initializeSimulator, fn);
  assert.equal(sim.maskForWidth, fnBigInt);
  assert.equal(watch.addBreakpoint, fn);
  assert.equal(watch.renderBreakpoints, fn);
});
