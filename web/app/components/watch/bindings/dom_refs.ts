export function createWatchDomRefs(documentRef = globalThis.document) {
  return {
    watchSignal: documentRef.getElementById('watchSignal'),
    addWatchBtn: documentRef.getElementById('addWatchBtn'),
    watchList: documentRef.getElementById('watchList'),
    bpSignal: documentRef.getElementById('bpSignal'),
    bpValue: documentRef.getElementById('bpValue'),
    addBpBtn: documentRef.getElementById('addBpBtn'),
    clearBpBtn: documentRef.getElementById('clearBpBtn'),
    bpList: documentRef.getElementById('bpList'),
    watchTableBody: documentRef.getElementById('watchTableBody'),
    eventLog: documentRef.getElementById('eventLog')
  };
}
