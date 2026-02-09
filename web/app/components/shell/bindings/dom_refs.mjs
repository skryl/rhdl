export function createShellDomRefs(documentRef = globalThis.document) {
  return {
    appShell: documentRef.getElementById('appShell'),
    viewer: documentRef.querySelector('.viewer'),
    controlsPanel: documentRef.getElementById('controlsPanel'),
    sidebarToggleBtn: documentRef.getElementById('sidebarToggleBtn'),
    terminalToggleBtn: documentRef.getElementById('terminalToggleBtn'),
    terminalPanel: documentRef.getElementById('terminalPanel'),
    terminalOutput: documentRef.getElementById('terminalOutput'),
    terminalInput: documentRef.getElementById('terminalInput'),
    terminalRunBtn: documentRef.getElementById('terminalRunBtn'),
    themeSelect: documentRef.getElementById('themeSelect'),
    tabButtons: Array.from(documentRef.querySelectorAll('.tab-btn')),
    tabPanels: Array.from(documentRef.querySelectorAll('.tab-panel'))
  };
}
