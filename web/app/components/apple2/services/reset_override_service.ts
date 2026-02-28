function requireFn(name, fn) {
  if (typeof fn !== 'function') {
    throw new Error(`createApple2ResetOverrideService requires function: ${name}`);
  }
}

export function createApple2ResetOverrideService({
  dom,
  setMemoryFollowPcState,
  getApple2ProgramCounter,
  parsePcLiteral,
  hexWord,
  ensureApple2Ready,
  romResetService,
  performApple2ResetSequence,
  refreshApple2UiState,
  setMemoryDumpStatus,
  setMemoryResetVectorInput,
  log
} = {}) {
  if (!dom) {
    throw new Error('createApple2ResetOverrideService requires dom');
  }
  requireFn('setMemoryFollowPcState', setMemoryFollowPcState);
  requireFn('getApple2ProgramCounter', getApple2ProgramCounter);
  requireFn('parsePcLiteral', parsePcLiteral);
  requireFn('hexWord', hexWord);
  requireFn('ensureApple2Ready', ensureApple2Ready);
  if (!romResetService || typeof romResetService.applySnapshotStartPc !== 'function') {
    throw new Error('createApple2ResetOverrideService requires romResetService.applySnapshotStartPc');
  }
  requireFn('performApple2ResetSequence', performApple2ResetSequence);
  requireFn('refreshApple2UiState', refreshApple2UiState);
  requireFn('setMemoryDumpStatus', setMemoryDumpStatus);
  requireFn('setMemoryResetVectorInput', setMemoryResetVectorInput);
  requireFn('log', log);

  async function resetApple2WithMemoryVectorOverride() {
    if (!ensureApple2Ready()) {
      return false;
    }

    const pcBefore = getApple2ProgramCounter();
    const raw = String(dom.memoryResetVector?.value || '').trim();
    let requestedPc = null;
    let usedOverride = false;

    if (raw) {
      requestedPc = parsePcLiteral(raw);
      if (requestedPc == null) {
        const msg = `Invalid reset vector "${raw}". Use $B82A, 0xB82A, or decimal.`;
        setMemoryDumpStatus(msg);
        log(msg);
        return false;
      }

      const pcStatus = await romResetService.applySnapshotStartPc(requestedPc);
      if (!pcStatus.applied) {
        const msg = `Could not apply reset vector $${hexWord(requestedPc)} (${pcStatus.reason}).`;
        setMemoryDumpStatus(msg);
        log(msg);
        return false;
      }
      usedOverride = true;
      setMemoryResetVectorInput(pcStatus.pc);
    }

    const resetInfo = performApple2ResetSequence({ releaseCycles: 0 });
    const pcAfter = Number.isFinite(resetInfo?.pcAfter)
      ? (resetInfo.pcAfter & 0xffff)
      : getApple2ProgramCounter();

    if (pcAfter != null) {
      setMemoryFollowPcState(true);
      if (dom.memoryFollowPc) {
        dom.memoryFollowPc.checked = true;
      }
      if (dom.memoryStart) {
        dom.memoryStart.value = `0x${hexWord(pcAfter)}`;
      }
    }

    refreshApple2UiState();

    const beforePart = pcBefore != null ? `$${hexWord(pcBefore)}` : 'n/a';
    const afterPart = pcAfter != null ? `$${hexWord(pcAfter)}` : 'n/a';
    const transitionPart = ` PC ${beforePart} -> ${afterPart}.`;
    const msg = usedOverride
      ? `Reset complete using vector $${hexWord(requestedPc)}.${transitionPart}`
      : `Reset complete using current ROM reset vector.${transitionPart}`;
    setMemoryDumpStatus(msg);
    if (dom.memoryStatus) {
      dom.memoryStatus.textContent = msg;
    }
    log(msg);
    return true;
  }

  return {
    resetApple2WithMemoryVectorOverride
  };
}
