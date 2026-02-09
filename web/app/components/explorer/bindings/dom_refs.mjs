export function createExplorerDomRefs(documentRef = globalThis.document) {
  return {
    componentTree: documentRef.getElementById('componentTree'),
    componentTitle: documentRef.getElementById('componentTitle'),
    componentMeta: documentRef.getElementById('componentMeta'),
    componentSignalMeta: documentRef.getElementById('componentSignalMeta'),
    componentSignalBody: documentRef.getElementById('componentSignalBody'),
    componentGraphTitle: documentRef.getElementById('componentGraphTitle'),
    componentGraphMeta: documentRef.getElementById('componentGraphMeta'),
    componentGraphTopBtn: documentRef.getElementById('componentGraphTopBtn'),
    componentGraphUpBtn: documentRef.getElementById('componentGraphUpBtn'),
    componentGraphFocusPath: documentRef.getElementById('componentGraphFocusPath'),
    componentVisual: documentRef.getElementById('componentVisual'),
    componentLiveSignals: documentRef.getElementById('componentLiveSignals'),
    componentConnectionMeta: documentRef.getElementById('componentConnectionMeta'),
    componentConnectionBody: documentRef.getElementById('componentConnectionBody'),
    componentCode: documentRef.getElementById('componentCode')
  };
}
