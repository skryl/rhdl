export function createApple2DomRefs(documentRef = globalThis.document) {
  return {
    apple2TextScreen: documentRef.getElementById('apple2TextScreen'),
    apple2HiresCanvas: documentRef.getElementById('apple2HiresCanvas'),
    apple2KeyInput: documentRef.getElementById('apple2KeyInput'),
    apple2SendKeyBtn: documentRef.getElementById('apple2SendKeyBtn'),
    apple2ClearKeysBtn: documentRef.getElementById('apple2ClearKeysBtn'),
    apple2KeyStatus: documentRef.getElementById('apple2KeyStatus'),
    apple2DebugBody: documentRef.getElementById('apple2DebugBody'),
    apple2SpeakerToggles: documentRef.getElementById('apple2SpeakerToggles'),
    toggleHires: documentRef.getElementById('toggleHires'),
    toggleColor: documentRef.getElementById('toggleColor'),
    toggleSound: documentRef.getElementById('toggleSound'),
    memoryDumpFile: documentRef.getElementById('memoryDumpFile'),
    memoryDumpOffset: documentRef.getElementById('memoryDumpOffset'),
    memoryDumpLoadBtn: documentRef.getElementById('memoryDumpLoadBtn'),
    memoryDumpSaveBtn: documentRef.getElementById('memoryDumpSaveBtn'),
    memorySnapshotSaveBtn: documentRef.getElementById('memorySnapshotSaveBtn'),
    memoryDumpLoadLastBtn: documentRef.getElementById('memoryDumpLoadLastBtn'),
    memoryResetVector: documentRef.getElementById('memoryResetVector'),
    memoryResetBtn: documentRef.getElementById('memoryResetBtn'),
    loadKaratekaBtn: documentRef.getElementById('loadKaratekaBtn'),
    memoryDumpStatus: documentRef.getElementById('memoryDumpStatus')
  };
}
