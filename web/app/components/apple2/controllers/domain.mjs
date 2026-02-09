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
  saveApple2MemoryDump,
  saveApple2MemorySnapshot,
  loadLastSavedApple2Dump,
  loadKaratekaDump,
  resetApple2WithMemoryVectorOverride
} = {}) {
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
    saveMemoryDump: saveApple2MemoryDump,
    saveMemorySnapshot: saveApple2MemorySnapshot,
    loadLastSavedDump: loadLastSavedApple2Dump,
    loadKaratekaDump,
    resetWithMemoryVectorOverride: resetApple2WithMemoryVectorOverride
  };
}
