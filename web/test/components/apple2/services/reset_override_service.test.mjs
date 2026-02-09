import test from 'node:test';
import assert from 'node:assert/strict';
import { createApple2ResetOverrideService } from '../../../../app/components/apple2/services/reset_override_service.mjs';

test('apple2 reset override service validates reset vector format', async () => {
  let status = '';
  const service = createApple2ResetOverrideService({
    dom: {
      memoryResetVector: { value: 'oops' },
      memoryFollowPc: { checked: false },
      memoryStart: { value: '' },
      memoryStatus: { textContent: '' }
    },
    setMemoryFollowPcState: () => {},
    getApple2ProgramCounter: () => 0,
    parsePcLiteral: () => null,
    hexWord: (value) => Number(value).toString(16).toUpperCase().padStart(4, '0'),
    ensureApple2Ready: () => true,
    romResetService: { applySnapshotStartPc: async () => ({ applied: false, reason: 'invalid' }) },
    performApple2ResetSequence: () => ({ pcAfter: 0 }),
    refreshApple2UiState: () => {},
    setMemoryDumpStatus: (message) => {
      status = message;
    },
    setMemoryResetVectorInput: () => {},
    log: () => {}
  });

  const ok = await service.resetApple2WithMemoryVectorOverride();
  assert.equal(ok, false);
  assert.match(status, /Invalid reset vector/);
});

test('apple2 reset override service applies vector and updates memory pane', async () => {
  let followState = false;
  const dom = {
    memoryResetVector: { value: '0xB82A' },
    memoryFollowPc: { checked: false },
    memoryStart: { value: '' },
    memoryStatus: { textContent: '' }
  };
  const service = createApple2ResetOverrideService({
    dom,
    setMemoryFollowPcState: (value) => {
      followState = value;
    },
    getApple2ProgramCounter: () => 0xB849,
    parsePcLiteral: () => 0xB82A,
    hexWord: (value) => Number(value).toString(16).toUpperCase().padStart(4, '0'),
    ensureApple2Ready: () => true,
    romResetService: {
      applySnapshotStartPc: async () => ({ applied: true, pc: 0xB82A, reason: 'ok' })
    },
    performApple2ResetSequence: () => ({ pcAfter: 0xB82A }),
    refreshApple2UiState: () => {},
    setMemoryDumpStatus: () => {},
    setMemoryResetVectorInput: () => {},
    log: () => {}
  });

  const ok = await service.resetApple2WithMemoryVectorOverride();
  assert.equal(ok, true);
  assert.equal(followState, true);
  assert.equal(dom.memoryFollowPc.checked, true);
  assert.equal(dom.memoryStart.value, '0xB82A');
  assert.match(dom.memoryStatus.textContent, /Reset complete using vector/);
});
