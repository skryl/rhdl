export function createRunnerDomRefs(documentRef = globalThis.document) {
  return {
    backendSelect: documentRef.getElementById('backendSelect'),
    backendStatus: documentRef.getElementById('backendStatus'),
    runnerSelect: documentRef.getElementById('runnerSelect'),
    loadRunnerBtn: documentRef.getElementById('loadRunnerBtn'),
    runnerStatus: documentRef.getElementById('runnerStatus'),
    irSourceSection: documentRef.getElementById('irSourceSection'),
    irJson: documentRef.getElementById('irJson'),
    irFileInput: documentRef.getElementById('irFileInput'),
    sampleSelect: documentRef.getElementById('sampleSelect'),
    loadSampleBtn: documentRef.getElementById('loadSampleBtn')
  };
}
