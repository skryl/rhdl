function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2UiStateService requires function: ${name}`);
  }
}

export function createApple2UiStateService({
  dom,
  state,
  runtime,
  parsePcLiteral,
  hexWord,
  refreshApple2Screen,
  refreshApple2Debug,
  refreshMemoryView,
  refreshWatchTable,
  refreshStatus
} = {}) {
  if (!dom || !state || !runtime) {
    throw new Error('createApple2UiStateService requires dom/state/runtime');
  }
  requireFn('parsePcLiteral', parsePcLiteral);
  requireFn('hexWord', hexWord);
  requireFn('refreshApple2Screen', refreshApple2Screen);
  requireFn('refreshApple2Debug', refreshApple2Debug);
  requireFn('refreshMemoryView', refreshMemoryView);
  requireFn('refreshWatchTable', refreshWatchTable);
  requireFn('refreshStatus', refreshStatus);

  function isApple2UiEnabled() {
    return state.apple2.enabled && runtime.sim?.apple2_mode?.();
  }

  function updateIoToggleUi() {
    const active = isApple2UiEnabled();
    if (dom.toggleHires) {
      dom.toggleHires.checked = !!state.apple2.displayHires;
      dom.toggleHires.disabled = !active;
    }
    if (dom.toggleColor) {
      dom.toggleColor.checked = !!state.apple2.displayColor;
      dom.toggleColor.disabled = !active || !state.apple2.displayHires;
    }
    if (dom.toggleSound) {
      dom.toggleSound.checked = !!state.apple2.soundEnabled;
      dom.toggleSound.disabled = !active;
    }
    if (dom.apple2TextScreen) {
      dom.apple2TextScreen.hidden = active && state.apple2.displayHires;
    }
    if (dom.apple2HiresCanvas) {
      dom.apple2HiresCanvas.hidden = !(active && state.apple2.displayHires);
    }
  }

  function setMemoryDumpStatus(message) {
    if (dom.memoryDumpStatus) {
      dom.memoryDumpStatus.textContent = message || '';
    }
  }

  function setMemoryResetVectorInput(value) {
    if (!dom.memoryResetVector) {
      return;
    }
    const parsed = parsePcLiteral(value);
    dom.memoryResetVector.value = parsed == null ? '' : `0x${hexWord(parsed)}`;
  }

  function refreshApple2UiState() {
    refreshApple2Screen();
    refreshApple2Debug();
    refreshMemoryView();
    refreshWatchTable();
    refreshStatus();
  }

  function formatHex16(value) {
    return hexWord(value);
  }

  return {
    isApple2UiEnabled,
    updateIoToggleUi,
    setMemoryDumpStatus,
    setMemoryResetVectorInput,
    refreshApple2UiState,
    formatHex16
  };
}
