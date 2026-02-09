export function createSimDomRefs(documentRef = globalThis.document) {
  return {
    initBtn: documentRef.getElementById('initBtn'),
    resetBtn: documentRef.getElementById('resetBtn'),
    stepBtn: documentRef.getElementById('stepBtn'),
    runBtn: documentRef.getElementById('runBtn'),
    pauseBtn: documentRef.getElementById('pauseBtn'),
    stepTicks: documentRef.getElementById('stepTicks'),
    runBatch: documentRef.getElementById('runBatch'),
    uiUpdateCycles: documentRef.getElementById('uiUpdateCycles'),
    clockSignal: documentRef.getElementById('clockSignal'),
    simStatus: documentRef.getElementById('simStatus'),
    traceStatus: documentRef.getElementById('traceStatus'),
    traceStartBtn: documentRef.getElementById('traceStartBtn'),
    traceStopBtn: documentRef.getElementById('traceStopBtn'),
    traceClearBtn: documentRef.getElementById('traceClearBtn'),
    downloadVcdBtn: documentRef.getElementById('downloadVcdBtn'),
    canvasWrap: documentRef.getElementById('canvasWrap')
  };
}
