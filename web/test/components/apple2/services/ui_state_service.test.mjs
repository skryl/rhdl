import test from 'node:test';
import assert from 'node:assert/strict';
import { createApple2UiStateService } from '../../../../app/components/apple2/services/ui_state_service.mjs';

test('apple2 ui state service updates toggles and status fields', () => {
  const calls = [];
  const dom = {
    toggleHires: { checked: false, disabled: true },
    toggleColor: { checked: false, disabled: true },
    toggleSound: { checked: false, disabled: true },
    apple2TextScreen: { hidden: false },
    apple2HiresCanvas: { hidden: true },
    memoryDumpStatus: { textContent: '' },
    memoryResetVector: { value: '' }
  };
  const state = {
    apple2: {
      enabled: true,
      displayHires: true,
      displayColor: true,
      soundEnabled: false
    }
  };
  const runtime = { sim: { apple2_mode: () => true } };
  const service = createApple2UiStateService({
    dom,
    state,
    runtime,
    parsePcLiteral: (value) => Number.parseInt(String(value).replace(/^0x/i, ''), 16),
    hexWord: (value) => Number(value).toString(16).toUpperCase().padStart(4, '0'),
    refreshApple2Screen: () => calls.push('screen'),
    refreshApple2Debug: () => calls.push('debug'),
    refreshMemoryView: () => calls.push('memory'),
    refreshWatchTable: () => calls.push('watch'),
    refreshStatus: () => calls.push('status')
  });

  assert.equal(service.isApple2UiEnabled(), true);
  service.updateIoToggleUi();
  assert.equal(dom.toggleHires.checked, true);
  assert.equal(dom.toggleHires.disabled, false);
  assert.equal(dom.toggleColor.disabled, false);
  assert.equal(dom.apple2TextScreen.hidden, true);
  assert.equal(dom.apple2HiresCanvas.hidden, false);

  service.setMemoryDumpStatus('ok');
  assert.equal(dom.memoryDumpStatus.textContent, 'ok');

  service.setMemoryResetVectorInput('0xB82A');
  assert.equal(dom.memoryResetVector.value, '0xB82A');

  service.refreshApple2UiState();
  assert.deepEqual(calls, ['screen', 'debug', 'memory', 'watch', 'status']);
});
