import {
  buildApple2SnapshotPayload,
  parseApple2SnapshotPayload,
  parsePcLiteral
} from '../lib/snapshot.mjs';
import { hexWord } from '../../../core/lib/numeric_utils.mjs';
import { createApple2DumpStorageService } from '../services/dump_storage_service.mjs';
import { createApple2DownloadService } from '../services/download_service.mjs';
import { createApple2RomResetService } from '../services/rom_reset_service.mjs';
import { createApple2UiStateService } from '../services/ui_state_service.mjs';
import { createApple2AudioRuntimeService } from '../services/audio_runtime_service.mjs';
import { createApple2SimRuntimeService } from '../services/sim_runtime_service.mjs';
import { createApple2ResetOverrideService } from '../services/reset_override_service.mjs';
import { createApple2DumpWorkflowService } from '../services/dump_workflow_service.mjs';

function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2OpsController requires function: ${name}`);
  }
}

const APPLE2_READY_MESSAGE = 'Load a runner with memory + I/O support first.';
const APPLE2_FIXTURE_ROOT = './assets/fixtures/apple2';

export function createApple2OpsController({
  dom,
  state,
  runtime,
  APPLE2_RAM_BYTES,
  KARATEKA_PC,
  LAST_APPLE2_DUMP_KEY,
  setApple2SoundEnabledState,
  setMemoryFollowPcState,
  setCycleState,
  setUiCyclesPendingState,
  setRunningState,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  refreshWatchTable,
  refreshStatus,
  getApple2ProgramCounter,
  currentRunnerPreset,
  log,
  fetchImpl = globalThis.fetch,
  windowRef = globalThis.window,
  documentRef = globalThis.document
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2OpsController requires dom/state/runtime');
  }
  requireFn('setApple2SoundEnabledState', setApple2SoundEnabledState);
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('setCycleState', setCycleState);
  requireFn('setUiCyclesPendingState', setUiCyclesPendingState);
  requireFn('setRunningState', setRunningState);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('refreshStatus', refreshStatus);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('currentRunnerPreset', currentRunnerPreset);
  requireFn('log', log);
  requireFn('fetchImpl', fetchImpl);

  const uiStateService = createApple2UiStateService({
    dom,
    state,
    runtime,
    parsePcLiteral,
    hexWord,
    refreshApple2Screen,
    refreshApple2Debug,
    refreshMemoryView,
    refreshWatchTable,
    refreshStatus
  });

  function ensureApple2Ready(message = APPLE2_READY_MESSAGE) {
    const hasMemoryApi = runtime.sim
      && (typeof runtime.sim.memory_mode !== 'function' || runtime.sim.memory_mode() != null);
    if (runtime.sim && uiStateService.isApple2UiEnabled() && hasMemoryApi) {
      return true;
    }
    uiStateService.setMemoryDumpStatus(message);
    return false;
  }

  const dumpStorageService = createApple2DumpStorageService({
    storageKey: LAST_APPLE2_DUMP_KEY,
    windowRef,
    buildSnapshotPayload: buildApple2SnapshotPayload,
    parseSnapshotPayload: parseApple2SnapshotPayload,
    log
  });

  const downloadService = createApple2DownloadService({
    windowRef,
    documentRef
  });

  const romResetService = createApple2RomResetService({
    state,
    runtime,
    currentRunnerPreset,
    fetchImpl,
    parsePcLiteral,
    isApple2UiEnabled: uiStateService.isApple2UiEnabled,
    fixtureRoot: APPLE2_FIXTURE_ROOT
  });

  const simRuntimeService = createApple2SimRuntimeService({
    state,
    runtime,
    APPLE2_RAM_BYTES,
    setRunningState,
    setCycleState,
    setUiCyclesPendingState,
    getApple2ProgramCounter,
    ensureApple2Ready,
    setMemoryDumpStatus: uiStateService.setMemoryDumpStatus,
    refreshApple2UiState: uiStateService.refreshApple2UiState,
    log
  });

  const audioRuntimeService = createApple2AudioRuntimeService({
    state,
    setApple2SoundEnabledState,
    updateIoToggleUi: uiStateService.updateIoToggleUi,
    log,
    windowRef
  });

  const resetOverrideService = createApple2ResetOverrideService({
    dom,
    setMemoryFollowPcState,
    getApple2ProgramCounter,
    parsePcLiteral,
    hexWord,
    ensureApple2Ready,
    romResetService,
    performApple2ResetSequence: simRuntimeService.performApple2ResetSequence,
    refreshApple2UiState: uiStateService.refreshApple2UiState,
    setMemoryDumpStatus: uiStateService.setMemoryDumpStatus,
    setMemoryResetVectorInput: uiStateService.setMemoryResetVectorInput,
    log
  });

  const dumpWorkflowService = createApple2DumpWorkflowService({
    dom,
    state,
    runtime,
    APPLE2_RAM_BYTES,
    KARATEKA_PC,
    dumpStorageService,
    downloadService,
    romResetService,
    getApple2ProgramCounter,
    ensureApple2Ready,
    setMemoryDumpStatus: uiStateService.setMemoryDumpStatus,
    setMemoryResetVectorInput: uiStateService.setMemoryResetVectorInput,
    loadApple2MemoryDumpBytes: simRuntimeService.loadApple2MemoryDumpBytes,
    log,
    fetchImpl,
    fixtureRoot: APPLE2_FIXTURE_ROOT
  });

  function apple2HiresLineAddress(row) {
    const section = Math.floor(row / 64);
    const rowInSection = row % 64;
    const group = Math.floor(rowInSection / 8);
    const lineInGroup = rowInSection % 8;
    return 0x2000 + (lineInGroup * 0x400) + (group * 0x80) + (section * 0x28);
  }

  return {
    isApple2UiEnabled: uiStateService.isApple2UiEnabled,
    updateIoToggleUi: uiStateService.updateIoToggleUi,
    apple2HiresLineAddress,
    setApple2SoundEnabled: audioRuntimeService.setApple2SoundEnabled,
    updateApple2SpeakerAudio: audioRuntimeService.updateApple2SpeakerAudio,
    setMemoryDumpStatus: uiStateService.setMemoryDumpStatus,
    setMemoryResetVectorInput: uiStateService.setMemoryResetVectorInput,
    saveApple2MemoryDump: dumpWorkflowService.saveApple2MemoryDump,
    saveApple2MemorySnapshot: dumpWorkflowService.saveApple2MemorySnapshot,
    loadApple2DumpOrSnapshotFile: dumpWorkflowService.loadApple2DumpOrSnapshotFile,
    loadLastSavedApple2Dump: dumpWorkflowService.loadLastSavedApple2Dump,
    resetApple2WithMemoryVectorOverride: resetOverrideService.resetApple2WithMemoryVectorOverride,
    performApple2ResetSequence: simRuntimeService.performApple2ResetSequence,
    loadApple2MemoryDumpBytes: simRuntimeService.loadApple2MemoryDumpBytes,
    loadKaratekaDump: dumpWorkflowService.loadKaratekaDump
  };
}
