import test from 'node:test';
import assert from 'node:assert/strict';

import { bindMemoryBindings } from '../../app/bindings/memory_bindings.mjs';

function makeTarget() {
  return new EventTarget();
}

function makeDom() {
  return {
    memoryFollowPc: Object.assign(makeTarget(), { checked: false }),
    memoryRefreshBtn: makeTarget(),
    memoryDumpLoadBtn: makeTarget(),
    memoryDumpSaveBtn: makeTarget(),
    memorySnapshotSaveBtn: makeTarget(),
    memoryDumpLoadLastBtn: makeTarget(),
    loadKaratekaBtn: makeTarget(),
    memoryResetBtn: makeTarget(),
    memoryResetVector: makeTarget(),
    memoryDumpFile: makeTarget(),
    memoryWriteBtn: makeTarget(),
    memoryStatus: { textContent: '' },
    memoryWriteAddr: { value: '' },
    memoryWriteValue: { value: '' },
    memoryDumpOffset: { value: '' }
  };
}

test('bindMemoryBindings wires follow-pc change and supports cleanup', () => {
  const dom = makeDom();
  const calls = [];
  const runtime = { sim: null };
  const actions = {
    setMemoryFollowPcState: (value) => calls.push(['setFollowPc', value]),
    refreshMemoryView: () => calls.push(['refreshMemoryView']),
    scheduleReduxUxSync: (reason) => calls.push(['sync', reason]),
    setMemoryDumpStatus: () => calls.push(['setMemoryDumpStatus']),
    loadApple2DumpOrSnapshotFile: async () => {},
    saveApple2MemoryDump: async () => {},
    saveApple2MemorySnapshot: async () => {},
    loadLastSavedApple2Dump: async () => {},
    loadKaratekaDump: async () => {},
    resetApple2WithMemoryVectorOverride: async () => {},
    isSnapshotFileName: () => false,
    parseHexOrDec: () => -1,
    hexByte: () => '00',
    refreshApple2Screen: () => {},
    isApple2UiEnabled: () => false
  };

  const teardown = bindMemoryBindings({ dom, runtime, actions });

  dom.memoryFollowPc.checked = true;
  dom.memoryFollowPc.dispatchEvent(new Event('change'));

  assert.deepEqual(calls, [
    ['setFollowPc', true],
    ['refreshMemoryView'],
    ['sync', 'memoryFollowPc']
  ]);

  teardown();
  dom.memoryFollowPc.checked = false;
  dom.memoryFollowPc.dispatchEvent(new Event('change'));
  assert.equal(calls.length, 3);
});
