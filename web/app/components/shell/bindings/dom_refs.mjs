export function createShellDomRefs(documentRef = globalThis.document) {
  const terminalOutput = documentRef.getElementById('terminalOutput');
  return {
    appShell: documentRef.getElementById('appShell'),
    viewer: documentRef.querySelector('.viewer'),
    controlsPanel: documentRef.getElementById('controlsPanel'),
    sidebarToggleBtn: documentRef.getElementById('sidebarToggleBtn'),
    terminalToggleBtn: documentRef.getElementById('terminalToggleBtn'),
    terminalPanel: documentRef.getElementById('terminalPanel'),
    terminalResizeHandle: documentRef.getElementById('terminalResizeHandle'),
    terminalOutput,
    terminalInput: terminalOutput,
    terminalRunBtn: null,
    editorTab: documentRef.getElementById('editorTab'),
    editorVimWrap: documentRef.getElementById('editorVimWrap'),
    editorVimCanvas: documentRef.getElementById('editorVimCanvas'),
    editorVimInput: documentRef.getElementById('editorVimInput'),
    editorFallback: documentRef.getElementById('editorFallback'),
    editorExecuteBtn: documentRef.getElementById('editorExecuteBtn'),
    editorTerminalOutput: documentRef.getElementById('editorTerminalOutput'),
    editorTraceWrap: documentRef.getElementById('editorCanvasWrap'),
    editorStatus: documentRef.getElementById('editorStatus'),
    editorTraceMeta: documentRef.getElementById('editorTraceMeta'),
    themeSelect: documentRef.getElementById('themeSelect'),
    tabButtons: Array.from(documentRef.querySelectorAll('.tab-btn')),
    tabPanels: Array.from(documentRef.querySelectorAll('.tab-panel'))
  };
}
