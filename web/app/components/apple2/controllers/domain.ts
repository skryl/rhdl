interface Apple2DomainDeps {
  isApple2UiEnabled: (...args: unknown[]) => unknown;
  updateIoToggleUi: (...args: unknown[]) => unknown;
  refreshApple2Screen: (...args: unknown[]) => unknown;
  refreshApple2Debug: (...args: unknown[]) => unknown;
  refreshMemoryView: (...args: unknown[]) => unknown;
  setApple2SoundEnabled: (...args: unknown[]) => unknown;
  updateApple2SpeakerAudio: (...args: unknown[]) => unknown;
  queueApple2Key: (...args: unknown[]) => unknown;
  performApple2ResetSequence: (...args: unknown[]) => unknown;
  setMemoryDumpStatus: (...args: unknown[]) => unknown;
  loadApple2DumpOrSnapshotFile: (...args: unknown[]) => unknown;
  loadApple2DumpOrSnapshotAssetPath: (...args: unknown[]) => unknown;
  saveApple2MemoryDump: (...args: unknown[]) => unknown;
  saveApple2MemorySnapshot: (...args: unknown[]) => unknown;
  loadLastSavedApple2Dump: (...args: unknown[]) => unknown;
  loadKaratekaDump: (...args: unknown[]) => unknown;
  resetApple2WithMemoryVectorOverride: (...args: unknown[]) => unknown;
}

export function createApple2DomainController({
  isApple2UiEnabled,
  updateIoToggleUi,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  setApple2SoundEnabled,
  updateApple2SpeakerAudio,
  queueApple2Key,
  performApple2ResetSequence,
  setMemoryDumpStatus,
  loadApple2DumpOrSnapshotFile,
  loadApple2DumpOrSnapshotAssetPath,
  saveApple2MemoryDump,
  saveApple2MemorySnapshot,
  loadLastSavedApple2Dump,
  loadKaratekaDump,
  resetApple2WithMemoryVectorOverride
}: Partial<Apple2DomainDeps> = {}) {
  return {
    isUiEnabled: isApple2UiEnabled,
    updateIoToggleUi,
    refreshScreen: refreshApple2Screen,
    refreshDebug: refreshApple2Debug,
    refreshMemoryView,
    setSoundEnabled: setApple2SoundEnabled,
    updateSpeakerAudio: updateApple2SpeakerAudio,
    queueKey: queueApple2Key,
    performResetSequence: performApple2ResetSequence,
    setMemoryDumpStatus,
    loadDumpOrSnapshotFile: loadApple2DumpOrSnapshotFile,
    loadDumpOrSnapshotAssetPath: loadApple2DumpOrSnapshotAssetPath,
    saveMemoryDump: saveApple2MemoryDump,
    saveMemorySnapshot: saveApple2MemorySnapshot,
    loadLastSavedDump: loadLastSavedApple2Dump,
    loadKaratekaDump,
    resetWithMemoryVectorOverride: resetApple2WithMemoryVectorOverride
  };
}
