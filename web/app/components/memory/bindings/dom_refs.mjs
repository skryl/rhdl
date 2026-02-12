export function createMemoryDomRefs(documentRef = globalThis.document) {
  return {
    memoryStart: documentRef.getElementById('memoryStart'),
    memoryLength: documentRef.getElementById('memoryLength'),
    memoryFollowPc: documentRef.getElementById('memoryFollowPc'),
    memoryRefreshBtn: documentRef.getElementById('memoryRefreshBtn'),
    memoryDump: documentRef.getElementById('memoryDump'),
    memoryDumpAssetTree: documentRef.getElementById('memoryDumpAssetTree'),
    memoryDumpAssetPath: documentRef.getElementById('memoryDumpAssetPath'),
    memoryDisassembly: documentRef.getElementById('memoryDisassembly'),
    memoryWriteAddr: documentRef.getElementById('memoryWriteAddr'),
    memoryWriteValue: documentRef.getElementById('memoryWriteValue'),
    memoryWriteBtn: documentRef.getElementById('memoryWriteBtn'),
    memoryStatus: documentRef.getElementById('memoryStatus')
  };
}
